import { image } from '@kit.ImageKit';
import { transformIsolated, cancelIsolated, IsolatedPixels } from 'libvenerajs.so';
import { ImageScriptBridge } from '../source/ImageScriptBridge';
import { Log } from '../foundation/Log';

class ImageTransformRequest {
  trace: string;
  cancelled: boolean = false;
  encodedBytes: number = 0;
  decodedBytes: number = 0;
  resume: (() => void) | undefined = undefined;
  reject: ((error: Error) => void) | undefined = undefined;
  constructor(trace: string) { this.trace = trace; }
}

/** First-frame straight RGBA -> upstream Image API -> lossless PNG, like Android. */
export class ImageTransforms {
  private static active: number = 0;
  private static readonly REQUEST_LIMIT: number = 32;
  private static readonly BYTE_LIMIT: number = 128 * 1024 * 1024;
  // Admission bounds owned encoded-input/RGBA reservations, not total process
  // memory (ImageKit/native/output allocations and caller-owned data differ).
  private static encodedRetained: number = 0;
  private static decodedRetained: number = 0;
  private static readonly requests: Set<ImageTransformRequest> = new Set<ImageTransformRequest>();
  private static readonly waiters: ImageTransformRequest[] = [];
  private static async acquire(request: ImageTransformRequest): Promise<void> {
    if (ImageTransforms.active < 4) { ImageTransforms.active++; return; }
    await new Promise<void>((resolve: () => void, reject: (error: Error) => void) => {
      request.resume = resolve; request.reject = reject;
      ImageTransforms.waiters.push(request);
    });
  }
  private static release(): void {
    const next = ImageTransforms.waiters.shift();
    if (next !== undefined && next.resume !== undefined) {
      const resume = next.resume;
      next.resume = undefined; next.reject = undefined; resume();
    } else { ImageTransforms.active--; }
  }
  static cancel(trace: string): void {
    for (const request of ImageTransforms.requests) {
      if (request.trace !== trace) { continue; }
      request.cancelled = true;
      const index = ImageTransforms.waiters.indexOf(request);
      if (index >= 0) {
        ImageTransforms.waiters.splice(index, 1);
        const reject = request.reject;
        request.resume = undefined; request.reject = undefined;
        if (reject !== undefined) { reject(new Error('IMAGE_REQUEST_CANCELLED')); }
      }
    }
    cancelIsolated(trace);
    Log.audit(trace, '图片后台取消', '中断对应Trace的排队/解码/原生执行/编码请求，其他Trace不变');
  }

  static async apply(bytes: ArrayBuffer, script: string, trace: string,
    shouldContinue: () => boolean = (): boolean => true): Promise<ArrayBuffer> {
    if (!shouldContinue()) { throw new Error('IMAGE_REQUEST_CANCELLED'); }
    if (script.length === 0) { return bytes; }
    Log.audit(trace, '图片变换到达', `输入字节=${bytes.byteLength}；最多4个后台隔离会话；脚本内容不落盘`);
    if (ImageTransforms.requests.size >= ImageTransforms.REQUEST_LIMIT ||
      bytes.byteLength > ImageTransforms.BYTE_LIMIT - ImageTransforms.encodedRetained) {
      Log.audit(trace, '图片内存准入拒绝', '请求数32或保留输入128MiB预算已满；未排队或创建解码器，不退回原图');
      throw new Error('IMAGE_TRANSFORM_ADMISSION_LIMIT');
    }
    const request = new ImageTransformRequest(trace);
    request.encodedBytes = bytes.byteLength;
    ImageTransforms.encodedRetained += request.encodedBytes;
    ImageTransforms.requests.add(request);
    let acquired: boolean = false;
    const isCurrent = (): boolean => !request.cancelled && shouldContinue();
    try {
      await ImageTransforms.acquire(request);
      acquired = true;
      if (!isCurrent()) { throw new Error('IMAGE_REQUEST_CANCELLED'); }
      return await ImageTransforms.run(bytes, script, trace, isCurrent, request);
    }
    catch (error) {
      Log.audit(trace, '图片变换异常', '取消/解码/脚本/编码失败；拒绝使用原始乱序图片冒充成功');
      throw new Error(String(error));
    } finally {
      ImageTransforms.requests.delete(request);
      // Keep reservations through encoding: the native call may still have
      // retained the RGBA input until it settles. Exactly one outer finally
      // returns both reservations on queue cancellation and every error path.
      ImageTransforms.encodedRetained -= request.encodedBytes;
      ImageTransforms.decodedRetained -= request.decodedBytes;
      request.encodedBytes = 0; request.decodedBytes = 0;
      if (acquired) { ImageTransforms.release(); }
    }
  }

  private static async run(bytes: ArrayBuffer, script: string, trace: string,
    shouldContinue: () => boolean, request: ImageTransformRequest): Promise<ArrayBuffer> {
    const decoder = image.createImageSource(bytes);
    let pixelMap: image.PixelMap | undefined = undefined;
    let decoderReleased: boolean = false;
    try {
      const info = await decoder.getImageInfo();
      if (!shouldContinue()) { throw new Error('IMAGE_REQUEST_CANCELLED'); }
      const size = ImageScriptBridge.byteSize(info.size.width, info.size.height);
      if (size > ImageTransforms.BYTE_LIMIT - ImageTransforms.decodedRetained) {
        Log.audit(trace, '图片RGBA准入拒绝', '合计128MiB的输入RGBA预留已满；未创建PixelMap或RGBA缓冲区，不退回原图');
        throw new Error('IMAGE_TRANSFORM_RGBA_LIMIT');
      }
      request.decodedBytes = size;
      ImageTransforms.decodedRetained += size;
      pixelMap = await decoder.createPixelMap({ desiredPixelFormat: image.PixelMapFormat.RGBA_8888 });
      const rgba = new ArrayBuffer(size);
      await pixelMap.readPixelsToBuffer(rgba);
      const decoded = await pixelMap.getImageInfo();
      const premultiplied = decoded.alphaType === image.AlphaType.PREMUL;
      // Once RGBA has been copied, release ImageKit decoded memory before native
      // input/output surfaces coexist. Clear ownership first so finally cannot
      // release a resource twice, including when release itself rejects.
      const decodedPixel = pixelMap;
      pixelMap = undefined;
      await decodedPixel.release();
      decoderReleased = true;
      await decoder.release();
      if (!shouldContinue()) { throw new Error('IMAGE_REQUEST_CANCELLED'); }
      // Alpha conversion and all pixel loops/script execution happen natively
      // on the worker, not in the ArkUI thread or main source JS runtime.
      const output: IsolatedPixels = await transformIsolated(rgba, info.size.width, info.size.height, script, trace,
        premultiplied, 10000);
      if (!shouldContinue()) { throw new Error('IMAGE_REQUEST_CANCELLED'); }
      if (output.width <= 0 || output.height <= 0 || output.rgba.byteLength !== ImageScriptBridge.byteSize(output.width, output.height)) {
        throw new Error('后台图片变换结果无效');
      }
      try {
        const buffer: ArrayBuffer = output.rgba;
        const transformed = await image.createPixelMap(buffer, {
          size: { width: output.width, height: output.height }, srcPixelFormat: image.PixelMapFormat.RGBA_8888,
          pixelFormat: image.PixelMapFormat.RGBA_8888, alphaType: image.AlphaType.UNPREMUL
        });
        try {
          if (!shouldContinue()) { throw new Error('IMAGE_REQUEST_CANCELLED'); }
          const packer = image.createImagePacker();
          try {
            const encoded = await packer.packToData(transformed, { format: 'image/png', quality: 100 });
            if (!shouldContinue()) { throw new Error('IMAGE_REQUEST_CANCELLED'); }
            Log.audit(trace, '图片变换返回', `输出=${output.width}x${output.height}；PNG字节=${encoded.byteLength}`);
            return encoded;
          } finally { await packer.release(); }
        } finally { await transformed.release(); }
      } finally { Log.audit(trace, '图片后台会话释放', '独立引擎/原生句柄已在后台释放；不持有主引擎像素表'); }
    } finally {
      try {
        if (pixelMap !== undefined) { await pixelMap.release(); }
      } finally {
        if (!decoderReleased) { decoderReleased = true; await decoder.release(); }
      }
    }
  }
}
