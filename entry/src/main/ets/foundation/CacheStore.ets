import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { Log } from './Log';

/**
 * One disk-cache entry: byte size plus a logical LRU stamp.
 *
 * `lastUsed` is a monotonically increasing sequence number owned by the store,
 * not a wall-clock timestamp: eviction order stays deterministic and immune to
 * clock changes or to several writes landing inside the same millisecond.
 */
export class CacheEntry {
  size: number = 0;
  lastUsed: number = 0;
}

/** Snapshot rendered by the cache settings page. */
export class CacheStats {
  bytes: number = 0;
  entries: number = 0;
  maxBytes: number = 0;
}

/** Directory listing record used while (re)building the index. */
class CacheFileFacts {
  key: string = '';
  size: number = 0;
  mtime: number = 0;
}

/**
 * Size-accounted, LRU-evicting disk cache.
 *
 * Layout (one directory, one flat namespace):
 *   <dir>/<key><suffix>          entry payload (binary or UTF-8 text)
 *   <dir>/<key><suffix>.part     in-flight write, renamed atomically on success
 *   <dir>/.cache-index.json      accounting index, replaced atomically
 *   <dir>/.cache-index.json.part index write in flight
 *
 * Index format (exact, version 1):
 *   {"v":1,"seq":<logical clock>,"entries":[{"k":"<key>","s":<bytes>,"u":<lastUsed>}]}
 * Entries are unordered; `seq` is the highest `u` ever handed out, so LRU order
 * survives a restart. A missing, unreadable, truncated or wrong-version index is
 * never fatal: the store rebuilds it from the directory listing and falls back to
 * lazy adoption on `get()`. Directory files are authoritative for sizes; the
 * index only adds recency, so a stale index cannot over-report bytes.
 *
 * File names: keys that are already filename-safe (`[A-Za-z0-9_-]`, not starting
 * with `x`) map to `<key><suffix>` - this keeps the pre-existing image cache
 * files (`<sha256>.img`) readable across the upgrade. Every other key is stored
 * as `x<hex(utf8(key))><suffix>`, which is reversible, so a rebuild can recover
 * the original namespaced key (`details:<source>:<id>`).
 *
 * Failure policy: reads never throw (a cache miss, unreadable directory or
 * corrupt payload is just a miss); writes throw so callers can decide, and the
 * index write is best effort - losing it only costs LRU precision until the next
 * rebuild.
 */
export class CacheStore {
  /** Default total cap: 1 GiB. */
  static readonly DEFAULT_MAX_BYTES: number = 1024 * 1024 * 1024;
  static readonly DEFAULT_SUFFIX: string = '.img';
  private static readonly INDEX_VERSION: number = 1;
  private static readonly INDEX_NAME: string = '.cache-index.json';
  private static readonly PART_SUFFIX: string = '.part';
  private static readonly PLAIN_KEY: RegExp = /^[A-Za-z0-9_-]{1,96}$/;
  /** Coalesced index write delay; structural changes flush immediately. */
  private static readonly FLUSH_DELAY_MS: number = 1200;
  private static readonly instances: Map<string, CacheStore> = new Map<string, CacheStore>();

  private readonly directory: string;
  private readonly suffix: string;
  private readonly indexPath: string;
  private readonly entries: Map<string, CacheEntry> = new Map<string, CacheEntry>();
  private maxBytesValue: number;
  private totalBytes: number = 0;
  private sequence: number = 0;
  private loaded: boolean = false;
  private dirty: boolean = false;
  private flushTimer: number = -1;
  private evictedCount: number = 0;

  constructor(directory: string, suffix: string = CacheStore.DEFAULT_SUFFIX,
    maxBytes: number = CacheStore.DEFAULT_MAX_BYTES) {
    this.directory = directory;
    this.suffix = suffix.length > 0 ? suffix : CacheStore.DEFAULT_SUFFIX;
    this.indexPath = `${directory}/${CacheStore.INDEX_NAME}`;
    this.maxBytesValue = maxBytes > 0 ? Math.trunc(maxBytes) : CacheStore.DEFAULT_MAX_BYTES;
  }

  /**
   * One store per (directory, suffix) so the settings page and the image loader
   * always account the same files. The first caller wins the initial cap; call
   * `setMaxBytes()` afterwards to apply a persisted preference.
   */
  static shared(directory: string, suffix: string = CacheStore.DEFAULT_SUFFIX,
    maxBytes: number = CacheStore.DEFAULT_MAX_BYTES): CacheStore {
    const id = `${directory}\n${suffix}`;
    const existing = CacheStore.instances.get(id);
    if (existing !== undefined) {
      return existing;
    }
    const created = new CacheStore(directory, suffix, maxBytes);
    CacheStore.instances.set(id, created);
    return created;
  }

  get directoryPath(): string {
    return this.directory;
  }

  get indexFilePath(): string {
    return this.indexPath;
  }

  /** Configured cap in bytes. */
  maxBytes(): number {
    return this.maxBytesValue;
  }

  /** Accounted payload bytes (index file and `.part` leftovers excluded). */
  size(): number {
    this.load();
    return this.totalBytes;
  }

  entryCount(): number {
    this.load();
    return this.entries.size;
  }

  /** Entries evicted since this instance was created. */
  evictions(): number {
    return this.evictedCount;
  }

  stats(): CacheStats {
    this.load();
    const stats = new CacheStats();
    stats.bytes = this.totalBytes;
    stats.entries = this.entries.size;
    stats.maxBytes = this.maxBytesValue;
    return stats;
  }

  /** Keys ordered least-recently-used first. Exposed for diagnostics/tests. */
  keysByRecency(): string[] {
    this.load();
    return this.lruKeys();
  }

  has(key: string): boolean {
    if (key.length === 0) {
      return false;
    }
    this.load();
    if (this.entries.has(key)) {
      return true;
    }
    try {
      return fs.accessSync(this.pathFor(key));
    } catch (error) {
      return false;
    }
  }

  /**
   * Read one entry and mark it most-recently-used.
   *
   * Never throws: an unreadable payload is dropped and reported as a miss so the
   * caller can fall back to the network.
   */
  get(key: string): ArrayBuffer | undefined {
    if (key.length === 0) {
      return undefined;
    }
    this.load();
    const known = this.entries.get(key);
    try {
      const bytes = this.readFile(key);
      if (bytes === undefined) {
        if (known !== undefined) {
          this.forget(key);
          this.scheduleFlush();
        }
        return undefined;
      }
      if (known === undefined) {
        // Present on disk but not indexed yet (previous process wrote it, or the
        // index was unreadable): adopt it instead of re-downloading.
        this.adopt(key, bytes.byteLength);
      } else if (known.size !== bytes.byteLength) {
        this.totalBytes += bytes.byteLength - known.size;
        known.size = bytes.byteLength;
      }
      this.bump(key);
      return bytes;
    } catch (error) {
      this.forget(key);
      this.scheduleFlush();
      Log.warn('CacheStore', `缓存读取失败，按未命中处理：${CacheStore.messageOf(error)}`);
      return undefined;
    }
  }

  /**
   * Store one entry, enforcing the cap.
   *
   * Throws when the single entry is larger than the whole cap (evicting the rest
   * would not make it fit) or when the payload cannot be written; a write
   * failure leaves the previous accounting untouched.
   */
  put(key: string, bytes: ArrayBuffer): void {
    if (key.length === 0) {
      throw new Error('缓存键为空，拒绝写入');
    }
    const size = bytes.byteLength;
    if (size <= 0) {
      throw new Error('缓存内容为空，拒绝写入');
    }
    if (size > this.maxBytesValue) {
      throw new Error(`缓存单项 ${size} 字节超过上限 ${this.maxBytesValue} 字节，已拒绝写入`);
    }
    this.load();
    this.writeFile(key, bytes);
    const known = this.entries.get(key);
    if (known !== undefined) {
      this.totalBytes -= known.size;
    }
    const entry = new CacheEntry();
    entry.size = size;
    entry.lastUsed = this.nextSequence();
    this.entries.set(key, entry);
    this.totalBytes += size;
    if (this.evictInternal() > 0) {
      this.persistSync();
    } else {
      this.scheduleFlush();
    }
  }

  /** Mark an existing entry as recently used without reading it. */
  touch(key: string): void {
    this.load();
    if (!this.entries.has(key)) {
      return;
    }
    this.bump(key);
    this.scheduleFlush();
  }

  /** Delete one entry (payload + accounting). Returns false when absent. */
  remove(key: string): boolean {
    this.load();
    const removed = this.forget(key);
    this.persistSync();
    return removed;
  }

  /**
   * Delete every managed payload and reset the accounting.
   *
   * Only files this store owns are removed: the index, `.part` leftovers and any
   * unrelated file in the directory (downloads, history databases, logs) stay
   * untouched. Returns the number of payload files deleted.
   */
  clear(): number {
    this.load();
    let removed = 0;
    const facts = this.scanFiles();
    if (facts !== undefined) {
      for (let i = 0; i < facts.length; i++) {
        if (this.deleteFile(facts[i].key)) {
          removed++;
        }
      }
    }
    const leftovers = this.listNames();
    if (leftovers !== undefined) {
      for (let i = 0; i < leftovers.length; i++) {
        const name = leftovers[i];
        if (!name.endsWith(`${this.suffix}${CacheStore.PART_SUFFIX}`)) {
          continue;
        }
        try {
          fs.unlinkSync(`${this.directory}/${name}`);
        } catch (error) {
          Log.warn('CacheStore', `清理写入残留失败：${CacheStore.messageOf(error)}`);
        }
      }
    }
    this.entries.clear();
    this.totalBytes = 0;
    this.sequence = 0;
    this.evictedCount = 0;
    this.cancelFlush();
    this.dirty = false;
    try {
      if (fs.accessSync(this.indexPath)) {
        fs.unlinkSync(this.indexPath);
      }
    } catch (error) {
      Log.warn('CacheStore', `删除缓存索引失败：${CacheStore.messageOf(error)}`);
    }
    return removed;
  }

  /** Change the cap; evicts immediately when the new cap is already exceeded. */
  setMaxBytes(bytes: number): number {
    if (!Number.isFinite(bytes) || bytes <= 0) {
      throw new Error('缓存上限必须为正数');
    }
    this.maxBytesValue = Math.trunc(bytes);
    this.load();
    const evicted = this.evictInternal();
    this.persistSync();
    return evicted;
  }

  /** Evict least-recently-used entries until the accounted bytes fit the cap. */
  evictIfNeeded(): number {
    this.load();
    const evicted = this.evictInternal();
    if (evicted > 0) {
      this.persistSync();
    }
    return evicted;
  }

  /** Force the debounced index write; safe to call at any time. */
  flush(): void {
    if (!this.loaded || !this.dirty) {
      return;
    }
    this.persistSync();
  }

  // ---- internals ----

  private load(): void {
    if (this.loaded) {
      return;
    }
    this.loaded = true;
    let facts: CacheFileFacts[] | undefined = undefined;
    try {
      this.ensureDirectory();
      facts = this.scanFiles();
    } catch (error) {
      Log.warn('CacheStore', `缓存目录不可用，按空缓存继续：${CacheStore.messageOf(error)}`);
      facts = undefined;
    }
    const indexed = this.readIndex();
    if (facts === undefined) {
      if (!indexed) {
        this.entries.clear();
        this.totalBytes = 0;
        this.sequence = 0;
      }
      return;
    }
    if (indexed) {
      this.reconcile(facts);
    } else {
      this.rebuild(facts);
    }
  }

  private ensureDirectory(): void {
    if (fs.accessSync(this.directory)) {
      return;
    }
    fs.mkdirSync(this.directory, true);
  }

  private listNames(): string[] | undefined {
    try {
      return fs.listFileSync(this.directory);
    } catch (error) {
      return undefined;
    }
  }

  private scanFiles(): CacheFileFacts[] | undefined {
    const names = this.listNames();
    if (names === undefined) {
      return undefined;
    }
    const facts: CacheFileFacts[] = [];
    for (let i = 0; i < names.length; i++) {
      const name = names[i];
      const key = this.keyFromFileName(name);
      if (key === undefined) {
        continue;
      }
      let size = 0;
      let mtime = 0;
      try {
        const stat = fs.statSync(`${this.directory}/${name}`);
        if (!stat.isFile()) {
          continue;
        }
        size = stat.size;
        mtime = stat.mtime;
      } catch (error) {
        continue;
      }
      if (size <= 0) {
        continue;
      }
      const fact = new CacheFileFacts();
      fact.key = key;
      fact.size = size;
      fact.mtime = mtime;
      facts.push(fact);
    }
    return facts;
  }

  /**
   * Index + directory merge: the listing wins on sizes and existence, the index
   * only contributes recency, so a stale index can never over-report bytes.
   */
  private reconcile(facts: CacheFileFacts[]): void {
    const present: Map<string, number> = new Map<string, number>();
    for (let i = 0; i < facts.length; i++) {
      present.set(facts[i].key, facts[i].size);
    }
    const stale: string[] = [];
    for (const key of this.entries.keys()) {
      if (!present.has(key)) {
        stale.push(key);
      }
    }
    for (let i = 0; i < stale.length; i++) {
      this.entries.delete(stale[i]);
    }
    facts.sort((left: CacheFileFacts, right: CacheFileFacts): number => left.mtime - right.mtime);
    for (let i = 0; i < facts.length; i++) {
      const fact = facts[i];
      const known = this.entries.get(fact.key);
      if (known === undefined) {
        const entry = new CacheEntry();
        entry.size = fact.size;
        entry.lastUsed = this.nextSequence();
        this.entries.set(fact.key, entry);
      } else {
        known.size = fact.size;
      }
    }
    this.recomputeTotal();
  }

  /** No usable index: rebuild from the listing, oldest mtime first. */
  private rebuild(facts: CacheFileFacts[]): void {
    this.entries.clear();
    this.totalBytes = 0;
    this.sequence = 0;
    facts.sort((left: CacheFileFacts, right: CacheFileFacts): number => left.mtime - right.mtime);
    for (let i = 0; i < facts.length; i++) {
      const fact = facts[i];
      const entry = new CacheEntry();
      entry.size = fact.size;
      entry.lastUsed = this.nextSequence();
      this.entries.set(fact.key, entry);
      this.totalBytes += entry.size;
    }
  }

  private recomputeTotal(): void {
    let total = 0;
    for (const key of this.entries.keys()) {
      const entry = this.entries.get(key);
      if (entry !== undefined) {
        total += entry.size;
      }
    }
    this.totalBytes = total;
  }

  /** Returns true when a structurally valid index was loaded into memory. */
  private readIndex(): boolean {
    let text = '';
    try {
      if (!fs.accessSync(this.indexPath)) {
        return false;
      }
      text = fs.readTextSync(this.indexPath);
    } catch (error) {
      return false;
    }
    if (text.length === 0) {
      return false;
    }
    let root: Record<string, Object>;
    try {
      root = JSON.parse(text) as Record<string, Object>;
    } catch (error) {
      return false;
    }
    if (root === null || typeof root !== 'object') {
      return false;
    }
    const version = root['v'];
    if (typeof version !== 'number' || version !== CacheStore.INDEX_VERSION) {
      return false;
    }
    const rows = root['entries'];
    if (!Array.isArray(rows)) {
      return false;
    }
    const list = rows as Object[];
    const parsed: Map<string, CacheEntry> = new Map<string, CacheEntry>();
    let sequence = 0;
    const rawSequence = root['seq'];
    if (typeof rawSequence === 'number' && Number.isFinite(rawSequence) && rawSequence >= 0) {
      sequence = Math.trunc(rawSequence);
    }
    for (let i = 0; i < list.length; i++) {
      const row = list[i] as Record<string, Object>;
      if (row === null || typeof row !== 'object') {
        continue;
      }
      const key = row['k'];
      const size = row['s'];
      const used = row['u'];
      if (typeof key !== 'string' || key.length === 0) {
        continue;
      }
      if (typeof size !== 'number' || !Number.isFinite(size) || size < 0) {
        continue;
      }
      if (typeof used !== 'number' || !Number.isFinite(used) || used < 0) {
        continue;
      }
      const entry = new CacheEntry();
      entry.size = Math.trunc(size);
      entry.lastUsed = Math.trunc(used);
      if (entry.lastUsed > sequence) {
        sequence = entry.lastUsed;
      }
      parsed.set(key as string, entry);
    }
    this.entries.clear();
    for (const key of parsed.keys()) {
      const entry = parsed.get(key);
      if (entry !== undefined) {
        this.entries.set(key, entry);
      }
    }
    this.sequence = sequence;
    return true;
  }

  private persistSync(): void {
    if (!this.loaded) {
      return;
    }
    this.cancelFlush();
    try {
      this.ensureDirectory();
      const parts: string[] = [];
      for (const key of this.entries.keys()) {
        const entry = this.entries.get(key);
        if (entry === undefined) {
          continue;
        }
        parts.push(`{"k":${JSON.stringify(key)},"s":${entry.size},"u":${entry.lastUsed}}`);
      }
      const text = `{"v":${CacheStore.INDEX_VERSION},"seq":${this.sequence},"entries":[${parts.join(',')}]}`;
      const temporary = `${this.indexPath}${CacheStore.PART_SUFFIX}`;
      const handle = fs.openSync(temporary,
        fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(handle.fd, text);
      } finally {
        fs.closeSync(handle);
      }
      fs.renameSync(temporary, this.indexPath);
      this.dirty = false;
    } catch (error) {
      // Best effort: losing the index only costs LRU precision until the next
      // start rebuilds it from the directory listing.
      this.dirty = true;
      Log.warn('CacheStore', `缓存索引写入失败，保留内存记账：${CacheStore.messageOf(error)}`);
    }
  }

  /**
   * Coalesced index write. `put`/`touch` are hot paths (one per image) and the
   * index is O(entries), so they never block on it; eviction, removal, a cap
   * change and `clear()` flush immediately instead.
   */
  private scheduleFlush(): void {
    this.dirty = true;
    if (this.flushTimer >= 0) {
      return;
    }
    try {
      this.flushTimer = setTimeout((): void => {
        this.flushTimer = -1;
        if (this.dirty) {
          this.persistSync();
        }
      }, CacheStore.FLUSH_DELAY_MS);
    } catch (error) {
      // Runtime without timers (isolated unit-test sandbox): stay dirty and
      // flush on the next structural write or explicit flush().
      this.flushTimer = -1;
    }
  }

  private cancelFlush(): void {
    if (this.flushTimer < 0) {
      return;
    }
    try {
      clearTimeout(this.flushTimer);
    } catch (error) {
      // Ignore: the timer id is reset below either way.
    }
    this.flushTimer = -1;
  }

  private nextSequence(): number {
    this.sequence++;
    return this.sequence;
  }

  private bump(key: string): void {
    const entry = this.entries.get(key);
    if (entry === undefined) {
      return;
    }
    entry.lastUsed = this.nextSequence();
  }

  private adopt(key: string, size: number): void {
    const entry = new CacheEntry();
    entry.size = size;
    entry.lastUsed = this.nextSequence();
    this.entries.set(key, entry);
    this.totalBytes += size;
  }

  /** Drop one entry from memory and disk without persisting. */
  private forget(key: string): boolean {
    const entry = this.entries.get(key);
    if (entry === undefined) {
      return false;
    }
    this.entries.delete(key);
    this.totalBytes = Math.max(0, this.totalBytes - entry.size);
    this.dirty = true;
    this.deleteFile(key);
    return true;
  }

  private evictInternal(): number {
    if (this.totalBytes <= this.maxBytesValue) {
      return 0;
    }
    const order = this.lruKeys();
    let evicted = 0;
    for (let i = 0; i < order.length && this.totalBytes > this.maxBytesValue; i++) {
      if (this.forget(order[i])) {
        evicted++;
      }
    }
    this.evictedCount += evicted;
    return evicted;
  }

  private lruKeys(): string[] {
    const keys: string[] = [];
    for (const key of this.entries.keys()) {
      keys.push(key);
    }
    const table = this.entries;
    keys.sort((left: string, right: string): number => {
      const first = table.get(left);
      const second = table.get(right);
      const leftUsed = first === undefined ? 0 : first.lastUsed;
      const rightUsed = second === undefined ? 0 : second.lastUsed;
      if (leftUsed !== rightUsed) {
        return leftUsed - rightUsed;
      }
      return left < right ? -1 : (left > right ? 1 : 0);
    });
    return keys;
  }

  private pathFor(key: string): string {
    return `${this.directory}/${this.fileNameFor(key)}`;
  }

  private fileNameFor(key: string): string {
    if (CacheStore.PLAIN_KEY.test(key) && !key.startsWith('x')) {
      return `${key}${this.suffix}`;
    }
    return `x${CacheStore.hexEncode(key)}${this.suffix}`;
  }

  private keyFromFileName(name: string): string | undefined {
    if (!name.endsWith(this.suffix)) {
      return undefined;
    }
    const base = name.substring(0, name.length - this.suffix.length);
    if (base.length === 0) {
      return undefined;
    }
    if (base.startsWith('x')) {
      const decoded = CacheStore.hexDecode(base.substring(1));
      return decoded.length > 0 ? decoded : undefined;
    }
    return CacheStore.PLAIN_KEY.test(base) ? base : undefined;
  }

  private readFile(key: string): ArrayBuffer | undefined {
    const path = this.pathFor(key);
    if (!fs.accessSync(path)) {
      return undefined;
    }
    const handle = fs.openSync(path, fs.OpenMode.READ_ONLY);
    try {
      const size = fs.statSync(path).size;
      if (size <= 0) {
        return undefined;
      }
      const bytes = new ArrayBuffer(size);
      const count = fs.readSync(handle.fd, bytes);
      if (count === size) {
        return bytes;
      }
      if (count <= 0) {
        return undefined;
      }
      return bytes.slice(0, count);
    } finally {
      fs.closeSync(handle);
    }
  }

  private writeFile(key: string, bytes: ArrayBuffer): void {
    this.ensureDirectory();
    const path = this.pathFor(key);
    const temporary = `${path}${CacheStore.PART_SUFFIX}`;
    const handle = fs.openSync(temporary,
      fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(handle.fd, bytes);
    } finally {
      fs.closeSync(handle);
    }
    fs.renameSync(temporary, path);
    const written = fs.statSync(path).size;
    if (written !== bytes.byteLength) {
      throw new Error(`缓存写入不完整：期望 ${bytes.byteLength} 字节，实际 ${written} 字节`);
    }
  }

  private deleteFile(key: string): boolean {
    const path = this.pathFor(key);
    try {
      if (!fs.accessSync(path)) {
        return false;
      }
      fs.unlinkSync(path);
      return true;
    } catch (error) {
      Log.warn('CacheStore', `删除缓存文件失败：${CacheStore.messageOf(error)}`);
      return false;
    }
  }

  private static hexEncode(value: string): string {
    const bytes = new util.TextEncoder().encodeInto(value);
    let encoded = '';
    for (let i = 0; i < bytes.length; i++) {
      encoded += bytes[i].toString(16).padStart(2, '0');
    }
    return encoded;
  }

  private static hexDecode(hex: string): string {
    if (hex.length === 0 || hex.length % 2 !== 0) {
      return '';
    }
    const bytes = new Uint8Array(hex.length / 2);
    for (let i = 0; i < bytes.length; i++) {
      const code = parseInt(hex.substring(i * 2, i * 2 + 2), 16);
      if (Number.isNaN(code)) {
        return '';
      }
      bytes[i] = code;
    }
    return util.TextDecoder.create('utf-8').decodeToString(bytes);
  }

  private static messageOf(error: Object): string {
    return error instanceof Error ? error.message : String(error);
  }
}

/**
 * Namespaced text payloads on top of {@link CacheStore}: comic details JSON and
 * page lists ("看过的一切漫画都缓存封面详情正文").
 *
 * Keys:
 *   details:<sourceKey>:<comicId>            detail payload as returned by loadInfo
 *   pages:<sourceKey>:<comicId>:<chapterId>  ordered page URL list for one chapter
 *
 * Values are JSON text under namespaced keys. Two layers are offered:
 * `getText`/`putText` (and the per-kind variants) keep the payload opaque, while
 * `detailPayload`/`rememberDetail` and `pageList`/`rememberPageList` handle the
 * JSON parse for callers and treat a malformed payload as a miss.
 */
export class PayloadCache {
  private readonly store: CacheStore;

  constructor(store: CacheStore) {
    this.store = store;
  }

  static detailsKey(sourceKey: string, comicId: string): string {
    return `details:${sourceKey}:${comicId}`;
  }

  static pagesKey(sourceKey: string, comicId: string, chapterId: string): string {
    return `pages:${sourceKey}:${comicId}:${chapterId}`;
  }

  getText(key: string): string | undefined {
    const bytes = this.store.get(key);
    if (bytes === undefined) {
      return undefined;
    }
    try {
      return util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(bytes));
    } catch (error) {
      this.store.remove(key);
      Log.warn('PayloadCache', `缓存文本不能解码，已删除该项：${error instanceof Error ? error.message : String(error)}`);
      return undefined;
    }
  }

  putText(key: string, text: string): void {
    if (text.length === 0) {
      throw new Error('缓存文本为空，拒绝写入');
    }
    const encoded = new util.TextEncoder().encodeInto(text);
    const buffer = new ArrayBuffer(encoded.length);
    new Uint8Array(buffer).set(encoded);
    this.store.put(key, buffer);
  }

  getDetails(sourceKey: string, comicId: string): string | undefined {
    return this.getText(PayloadCache.detailsKey(sourceKey, comicId));
  }

  putDetails(sourceKey: string, comicId: string, json: string): void {
    this.putText(PayloadCache.detailsKey(sourceKey, comicId), json);
  }

  getPages(sourceKey: string, comicId: string, chapterId: string): string | undefined {
    return this.getText(PayloadCache.pagesKey(sourceKey, comicId, chapterId));
  }

  putPages(sourceKey: string, comicId: string, chapterId: string, json: string): void {
    this.putText(PayloadCache.pagesKey(sourceKey, comicId, chapterId), json);
  }

  removeDetails(sourceKey: string, comicId: string): boolean {
    return this.store.remove(PayloadCache.detailsKey(sourceKey, comicId));
  }

  /**
   * Raw `loadInfo` payload (the object a source script returned) or undefined.
   *
   * Callers must feed it to `ComicDetails.fromJson`; never cache the parsed
   * model instead - its `tags` is a Map and would not survive JSON.
   */
  detailPayload(sourceKey: string, comicId: string): Object | undefined {
    const text = this.getDetails(sourceKey, comicId);
    if (text === undefined) {
      return undefined;
    }
    let parsed: Object;
    try {
      parsed = JSON.parse(text) as Object;
    } catch (error) {
      this.store.remove(PayloadCache.detailsKey(sourceKey, comicId));
      return undefined;
    }
    if (parsed === null || typeof parsed !== 'object') {
      this.store.remove(PayloadCache.detailsKey(sourceKey, comicId));
      return undefined;
    }
    return parsed;
  }

  /** Remember one raw `loadInfo` payload; failures are the caller's to ignore. */
  rememberDetail(sourceKey: string, comicId: string, raw: Object): void {
    this.putDetails(sourceKey, comicId, JSON.stringify(raw));
  }

  /** Cached page URL list for one chapter, or undefined on miss/corruption. */
  pageList(sourceKey: string, comicId: string, chapterId: string): string[] | undefined {
    const text = this.getPages(sourceKey, comicId, chapterId);
    if (text === undefined) {
      return undefined;
    }
    let parsed: Object;
    try {
      parsed = JSON.parse(text) as Object;
    } catch (error) {
      this.store.remove(PayloadCache.pagesKey(sourceKey, comicId, chapterId));
      return undefined;
    }
    if (!Array.isArray(parsed)) {
      this.store.remove(PayloadCache.pagesKey(sourceKey, comicId, chapterId));
      return undefined;
    }
    const items = parsed as Object[];
    const images: string[] = [];
    for (let i = 0; i < items.length; i++) {
      if (typeof items[i] === 'string') {
        images.push(items[i] as string);
      }
    }
    return images.length > 0 ? images : undefined;
  }

  /** Remember one chapter's page list; an empty list is not cached. */
  rememberPageList(sourceKey: string, comicId: string, chapterId: string, images: string[]): void {
    if (images.length === 0) {
      return;
    }
    this.putPages(sourceKey, comicId, chapterId, JSON.stringify(images));
  }

  stats(): CacheStats {
    return this.store.stats();
  }
}
