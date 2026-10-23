import { image } from '@kit.ImageKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { CacheStore } from '../foundation/CacheStore';
import { Log } from '../foundation/Log';
import { CacheManager } from '../storage/CacheSettings';
import { HttpClient } from './HttpClient';
import { imageCacheKey } from './ImageCacheKey';
import { CookieJar } from './CookieJar';
import { ImageTransforms } from './ImageTransforms';
import { ImageRequestConfig } from '../source/ComicSource';
import { ImagePipeline } from './ImagePipeline';

/**
 * One consumer's hold on a decoded image.
 *
 * The loader owns every PixelMap it returns. A lease is idempotent and only
 * retires *this* consumer: another visible or reused component may still be
 * rendering the same cached map. Widgets therefore release the lease and never
 * call `release()` on `pixelMap` themselves.
 */
export class ImageLease {
  readonly pixelMap: image.PixelMap;
  private released: boolean = false;
  private readonly retire: () => void;
  constructor(pixelMap: image.PixelMap, retire: () => void) {
    this.pixelMap = pixelMap;
    this.retire = retire;
  }
  release(): void {
    if (this.released) { return; }
    this.released = true;
    this.retire();
  }
}

/** A shareable request is one whose bytes depend only on URL/headers/transform. */
function shareable(config: ImageRequestConfig): boolean {
  return config.method === 'GET' && config.data === undefined &&
    config.onResponse === undefined && config.onLoadFailed === undefined;
}

class SharedEntry {
  consumers: number = 0;
  settled: boolean = false;
  cancelled: boolean = false;
  promise: Promise<image.PixelMap> | undefined = undefined;
  cancel: () => void = (): void => {};
}

/**
 * Image loading with memory + disk cache.
 *
 * Dart original: lib/network/images.dart (`ImageDownloader`) plus the
 * ImageProvider classes. ArkUI's `Image` component accepts a PixelMap directly,
 * so this class resolves a URL to a PixelMap:
 *   - `file://` paths are decoded straight from the sandbox;
 *   - http(s) URLs are downloaded once into the shared disk cache and reused
 *     across app restarts, until that cache's byte cap evicts them by LRU.
 *
 * Source configuration is resolved before entry; required pixel scripts are
 * applied before writing cache, and their text is part of the hashed identity.
 *
 * Disk persistence goes through {@link CacheStore} (owned by `CacheManager`),
 * which provides byte accounting, the size cap and LRU eviction. A cache problem
 * is always a miss, never an image failure: `CacheStore.get` does not throw, and
 * a failed write is logged after the decoded image has already been produced.
 */
export class ImageLoader {
  /** Bounded producer concurrency: the reader mounts many images at once. */
  private static readonly SHARED_LIMIT: number = 4;
  private static active: number = 0;
  private static readonly waiting: (() => void)[] = [];
  /** In-flight shareable requests keyed by hashed identity. */
  private static readonly shared: Map<string, SharedEntry> = new Map<string, SharedEntry>();

  static cancelOwned(trace: string): void { ImageTransforms.cancel(trace); }
  static ownsRequest(config: ImageRequestConfig): boolean {
    // A cancellable transform must not borrow a shared in-flight native job:
    // cancelling consumer A could otherwise reject consumer B's same-URL image.
    return !shareable(config);
  }

  private static async acquireSlot(): Promise<void> {
    if (ImageLoader.active < ImageLoader.SHARED_LIMIT) { ImageLoader.active++; return; }
    await new Promise<void>((resolve: () => void) => { ImageLoader.waiting.push(resolve); });
  }

  private static releaseSlot(): void {
    const next = ImageLoader.waiting.shift();
    if (next !== undefined) { next(); } else { ImageLoader.active--; }
  }

  private static readonly memory: Map<string, image.PixelMap> = new Map<string, image.PixelMap>();
  private static readonly MEMORY_LIMIT: number = 24;
  private static readonly pending: Map<string, Promise<image.PixelMap>> = new Map<string, Promise<image.PixelMap>>();

  private static store: CacheStore | undefined = undefined;

  /**
   * Shared size-capped disk cache, or undefined when it is unavailable (no
   * AppContext yet, Previewer, unreadable sandbox). Images still load then; they
   * are simply not persisted, so a cache problem can never fail a picture.
   */
  private static diskCache(): CacheStore | undefined {
    if (ImageLoader.store !== undefined) {
      return ImageLoader.store;
    }
    try {
      ImageLoader.store = CacheManager.imageStore();
      return ImageLoader.store;
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      Log.warn('ImageLoader', `磁盘缓存不可用，本次只用内存缓存：${message}`);
      return undefined;
    }
  }

  private static async decodeBytes(bytes: ArrayBuffer): Promise<image.PixelMap> {
    const source = image.createImageSource(bytes);
    try { return await source.createPixelMap(); }
    finally { await source.release(); }
  }

  /**
   * Diagnostic note recorded with every cache write: which identity inputs
   * produced the key. Values are never logged (URLs, headers, cookies and pixel
   * script text stay off disk) - only presence and counts, so a future identity
   * change (`ImageCacheKey`) is diagnosable from the log without weakening it.
   */
  private static identityNote(key: string, headerCount: number, hasCookie: boolean,
    transformLength: number): string {
    return `键前缀=${key.substring(0, 8)}；头部数=${headerCount}；` +
      `Cookie=${hasCookie ? '参与身份' : '空'}；像素变换=${transformLength > 0 ? '参与身份' : '无'}`;
  }

  private static async decodeFile(path: string): Promise<image.PixelMap> {
    const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
    try {
      const source = image.createImageSource(file.fd);
      try { return await source.createPixelMap(); }
      finally { await source.release(); }
    } finally {
      fs.closeSync(file);
    }
  }

  private static remember(url: string, pixelMap: image.PixelMap): void {
    if (ImageLoader.memory.size >= ImageLoader.MEMORY_LIMIT) {
      const firstKey = ImageLoader.memory.keys().next().value as string;
      ImageLoader.memory.delete(firstKey);
    }
    ImageLoader.memory.set(url, pixelMap);
  }

  /**
   * Reference-counted acquisition used by reader/cover components.
   *
   * Shareable requests coalesce into one bounded producer, so a remount or a
   * second visible consumer of the same page does not download, de-obfuscate or
   * decode again. `shouldContinue` is only an advisory view check; the producer
   * keeps running while another consumer still holds a lease.
   */
  static async acquireRequest(config: ImageRequestConfig, trace: string,
    shouldContinue: () => boolean = (): boolean => true, thumbnail: boolean = false): Promise<ImageLease> {
    void thumbnail;
    if (!shouldContinue()) { throw new Error('IMAGE_REQUEST_CANCELLED'); }
    if (config.url.length === 0) { throw new Error('图片地址为空'); }
    if (!shareable(config)) {
      // Dynamic request: private pipeline run owned by exactly this consumer.
      const bytes = await ImagePipeline.fetch(config, trace, shouldContinue);
      const decoder = image.createImageSource(bytes);
      let pixel: image.PixelMap;
      try { pixel = await decoder.createPixelMap(); }
      finally { await decoder.release(); }
      let done = false;
      return new ImageLease(pixel, (): void => {
        if (done) { return; }
        done = true;
        ImageTransforms.cancel(trace);
        pixel.release().catch((error: Object) => {
          Log.audit(trace, '图片租赁释放异常', '动态请求PixelMap释放失败，不记录地址');
        });
      });
    }

    const key = imageCacheKey(config.url, config.headers, CookieJar.header(config.url), config.modifyImage);
    const cached = ImageLoader.memory.get(key);
    if (cached !== undefined) {
      Log.audit(trace, '图片租约返回', '命中已解码的内存缓存；未重复下载或变换');
      return new ImageLease(cached, (): void => {});
    }
    let entry = ImageLoader.shared.get(key);
    if (entry === undefined) {
      const created = new SharedEntry();
      created.promise = ImageLoader.produceShared(key, config, trace, created);
      ImageLoader.shared.set(key, created);
      entry = created;
    } else {
      Log.audit(trace, '图片租约合并', '相同身份已在下载/解码；共享同一次结果');
    }
    const joined = entry;
    joined.consumers++;
    let held = true;
    try {
      const pending = joined.promise;
      if (pending === undefined) { throw new Error('图片生产任务不可用'); }
      const pixel = await pending;
      if (joined.cancelled) { throw new Error('IMAGE_REQUEST_CANCELLED'); }
      return new ImageLease(pixel, (): void => {
        if (!held) { return; }
        held = false;
        ImageLoader.releaseConsumer(key, joined);
      });
    } catch (error) {
      if (held) { held = false; ImageLoader.releaseConsumer(key, joined); }
      throw new Error(String(error));
    }
  }

  private static releaseConsumer(key: string, entry: SharedEntry): void {
    entry.consumers--;
    if (entry.consumers > 0) { return; }
    if (!entry.settled) {
      // The last consumer left before the image existed: stop the transfer so a
      // fast scroll does not keep downloading pages nobody is looking at.
      entry.cancelled = true;
      entry.cancel();
      ImageLoader.shared.delete(key);
      return;
    }
    // Settled pixels stay in the memory cache for instant reuse.
    ImageLoader.shared.delete(key);
  }

  private static async produceShared(key: string, config: ImageRequestConfig, trace: string,
    entry: SharedEntry): Promise<image.PixelMap> {
    entry.cancel = (): void => { ImageTransforms.cancel(trace); };
    try {
      await ImageLoader.acquireSlot();
      try {
        if (entry.cancelled) { throw new Error('IMAGE_REQUEST_CANCELLED'); }
        const pixel = await ImageLoader.loadTransformed(config, key, trace);
        if (entry.cancelled) {
          pixel.release().catch((error: Object) => {
            Log.audit(trace, '图片晚到释放异常', '取消后完成的图片释放失败，不记录地址');
          });
          throw new Error('IMAGE_REQUEST_CANCELLED');
        }
        entry.settled = true;
        ImageLoader.remember(key, pixel);
        Log.audit(trace, '图片租约返回', '下载/变换/解码完成并加入内存缓存');
        return pixel;
      } finally { ImageLoader.releaseSlot(); }
    } catch (error) {
      Log.audit(trace, '图片租约异常', '读取/下载/变换/解码未完成；未返回成功图片');
      entry.settled = true;
      ImageLoader.shared.delete(key);
      throw new Error(String(error));
    }
  }

  /** Shared-path producer: disk cache first, then transform + atomic write. */
  private static async loadTransformed(config: ImageRequestConfig, key: string,
    trace: string): Promise<image.PixelMap> {
    const url = config.url;
    if (url.startsWith('file://')) {
      const path = url.substring('file://'.length);
      if (config.modifyImage.length === 0) { return ImageLoader.decodeFile(path); }
      const handle = fs.openSync(path, fs.OpenMode.READ_ONLY);
      let bytes: ArrayBuffer;
      try {
        bytes = new ArrayBuffer(fs.statSync(path).size);
        const count = fs.readSync(handle.fd, bytes);
        if (count !== bytes.byteLength) { throw new Error('本地图片读取不完整'); }
      } finally { fs.closeSync(handle); }
      const modified = await ImageTransforms.apply(bytes, config.modifyImage, trace);
      const decoder = image.createImageSource(modified);
      try { return await decoder.createPixelMap(); }
      finally { await decoder.release(); }
    }
    const store = ImageLoader.diskCache();
    if (store !== undefined) {
      const cached = store.get(key);
      if (cached !== undefined) {
        try { return await ImageLoader.decodeBytes(cached); }
        catch (error) {
          store.remove(key);
          Log.audit(trace, '缓存拒绝', '已有缓存不能解码，只删除当前项，重新下载一次');
        }
      }
    }
    const response = await HttpClient.getBytes(url, config.headers, trace);
    if (!response.ok || response.bytes === undefined) { throw new Error(`图片HTTP ${response.status}`); }
    const bytes = await ImageTransforms.apply(response.bytes, config.modifyImage, trace);
    const decoder = image.createImageSource(bytes);
    let pixelMap: image.PixelMap;
    try { pixelMap = await decoder.createPixelMap(); }
    finally { await decoder.release(); }
    if (store === undefined) {
      return pixelMap;
    }
    try {
      store.put(key, bytes);
      Log.audit(trace, '图片缓存保存', `有效图片已写入容量受限缓存；字节=${bytes.byteLength}；` +
        ImageLoader.identityNote(key, config.headers.size,
          CookieJar.header(config.url).length > 0, config.modifyImage.length));
    } catch (error) {
      // Oversized single entry or a full/unwritable disk: the picture still
      // renders, it just is not persisted.
      Log.audit(trace, '图片缓存跳过', '缓存未写入，图片已返回；下次重新下载');
    }
    return pixelMap;
  }

  static async loadRequest(config: ImageRequestConfig, trace: string,
    shouldContinue: () => boolean = (): boolean => true): Promise<image.PixelMap> {
    if (!shouldContinue()) {
      Log.audit(trace, '图片加载拒绝', '页面/任务已取消，未进入缓存/HTTP');
      throw new Error('IMAGE_REQUEST_CANCELLED');
    }
    if (!ImageLoader.ownsRequest(config)) {
      const shared = await ImageLoader.load(config.url, config.headers, config.modifyImage, trace);
      // The cache owns shared PixelMaps; a cancelled consumer must not release one.
      if (!shouldContinue()) { throw new Error('IMAGE_REQUEST_CANCELLED'); }
      return shared;
    }
    // Callbacks/bodies own cancellation and must not share an in-flight job.
    Log.audit(trace, '图片动态缓存策略', '有正文/回调/非GET，独立请求绕过共享缓存；保留逐阶段取消');
    const bytes = await ImagePipeline.fetch(config, trace, shouldContinue);
    const decoder = image.createImageSource(bytes);
    try {
      const pixelMap = await decoder.createPixelMap();
      if (!shouldContinue()) { await pixelMap.release(); throw new Error('IMAGE_REQUEST_CANCELLED'); }
      return pixelMap;
    } finally { await decoder.release(); }
  }

  /**
   * Resolve a page/cover URL to a PixelMap.
   * Throws when the resource cannot be fetched or decoded.
   */
  static async load(url: string, headers?: Map<string, string>, transform: string = '',
    trace: string = `image-${Date.now()}`): Promise<image.PixelMap> {
    Log.audit(trace, '图片加载到达', `本地=${url.startsWith('file://')}；像素变换=${transform.length > 0}；头部数=${headers?.size ?? 0}`);
    if (url.length === 0) {
      Log.audit(trace, '图片加载拒绝', '地址为空；未进入文件/网络层');
      throw new Error('图片地址为空');
    }
    const key = imageCacheKey(url, headers ?? new Map<string, string>(), CookieJar.header(url), transform);
    const cached = ImageLoader.memory.get(key);
    if (cached !== undefined) {
      Log.audit(trace, '图片加载返回', '命中会话隔离的内存缓存');
      return cached;
    }
    const pending = ImageLoader.pending.get(key);
    if (pending !== undefined) {
      Log.audit(trace, '图片加载合并', '相同身份已有请求，等待原请求；不并发覆盖缓存文件');
      return pending;
    }
    const request = ImageLoader.loadUncached(url, headers, transform, key, trace);
    ImageLoader.pending.set(key, request);
    try {
      const pixelMap = await request;
      ImageLoader.remember(key, pixelMap);
      Log.audit(trace, '图片加载返回', '解码完成并加入内存缓存');
      return pixelMap;
    } catch (error) {
      Log.audit(trace, '图片加载异常', '读取/下载/变换/解码未完成；不返回成功图片');
      throw new Error(String(error));
    } finally { ImageLoader.pending.delete(key); }
  }

  private static async loadUncached(url: string, headers: Map<string, string> | undefined, transform: string,
    key: string, trace: string): Promise<image.PixelMap> {
    if (url.startsWith('file://')) {
      const path = url.substring('file://'.length);
      if (transform.length === 0) { return ImageLoader.decodeFile(path); }
      const handle = fs.openSync(path, fs.OpenMode.READ_ONLY);
      let bytes: ArrayBuffer;
      try {
        bytes = new ArrayBuffer(fs.statSync(path).size);
        const count = fs.readSync(handle.fd, bytes);
        if (count !== bytes.byteLength) { throw new Error('本地图片读取不完整'); }
      } finally { fs.closeSync(handle); }
      const modified = await ImageTransforms.apply(bytes, transform, trace);
      const decoder = image.createImageSource(modified);
      try { return await decoder.createPixelMap(); }
      finally { await decoder.release(); }
    }
    const store = ImageLoader.diskCache();
    if (store !== undefined) {
      const cached = store.get(key);
      if (cached !== undefined) {
        try { return await ImageLoader.decodeBytes(cached); }
        catch (error) {
          store.remove(key);
          Log.audit(trace, '缓存拒绝', '已有缓存不能解码，只删除当前项，重新下载一次');
        }
      }
    }
    Log.audit(trace, '图片网络请求', '开始下载；URL、Cookie、授权头不落盘');
    const response = await HttpClient.getBytes(url, headers, trace);
    if (!response.ok || response.bytes === undefined) { throw new Error(`图片HTTP ${response.status}`); }
    const bytes = await ImageTransforms.apply(response.bytes, transform, trace);
    const decoder = image.createImageSource(bytes);
    let pixelMap: image.PixelMap;
    try { pixelMap = await decoder.createPixelMap(); }
    finally { await decoder.release(); }
    if (store === undefined) {
      return pixelMap;
    }
    try {
      store.put(key, bytes);
      Log.audit(trace, '图片缓存保存', `有效图片已写入容量受限缓存；字节=${bytes.byteLength}；` +
        ImageLoader.identityNote(key, headers?.size ?? 0,
          CookieJar.header(url).length > 0, transform.length));
    } catch (error) {
      Log.audit(trace, '图片缓存跳过', '缓存未写入，图片已返回；下次重新下载');
    }
    return pixelMap;
  }

  /** Best-effort warm-up used by the reader; failures are logged, not thrown. */
  static async preload(url: string, headers?: Map<string, string>): Promise<void> {
    try {
      await ImageLoader.load(url, headers);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      Log.warn('ImageLoader', `preload failed; URL omitted: ${message.replace(/https?:\/\/\S+/g, '[URL]')}`);
    }
  }

  static clearMemory(): void {
    ImageLoader.memory.clear();
  }
}
