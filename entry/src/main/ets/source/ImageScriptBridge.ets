import { Log } from '../foundation/Log';

/** RGBA byte surfaces implement upstream image_processing.dart without channel conversion. */
export class ImageSurface {
  width: number;
  height: number;
  bytes: Uint8Array;
  constructor(width: number, height: number, bytes: Uint8Array) {
    this.width = width; this.height = height; this.bytes = bytes;
  }
}

/** Only callable within one serialized modifyImage request; handles expire in finally. */
export class ImageScriptBridge {
  private static images: Map<number, ImageSurface> = new Map<number, ImageSurface>();
  private static nextKey: number = 1;
  private static trace: string = '';
  private static allocated: number = 0;
  private static readonly LIMIT: number = 128 * 1024 * 1024;

  static begin(surface: ImageSurface, trace: string): number {
    if (ImageScriptBridge.trace.length > 0) { throw new Error('图片变换会话不能重叠'); }
    ImageScriptBridge.trace = trace;
    Log.audit(trace, '图片桥入口', `尺寸=${surface.width}x${surface.height}；会话内存上限=${ImageScriptBridge.LIMIT}`);
    try { return ImageScriptBridge.put(surface); }
    catch (error) { ImageScriptBridge.end(); throw new Error(String(error)); }
  }

  static end(): void {
    Log.audit(ImageScriptBridge.trace, '图片桥释放', `释放句柄=${ImageScriptBridge.images.size}；字节=${ImageScriptBridge.allocated}`);
    ImageScriptBridge.images.clear();
    ImageScriptBridge.allocated = 0;
    ImageScriptBridge.trace = '';
  }

  static result(key: number): ImageSurface {
    const surface = ImageScriptBridge.images.get(key);
    if (surface === undefined) { throw new Error('图片脚本未返回本次会话中的Image'); }
    return surface;
  }

  private static integer(value: Object | undefined): number {
    if (typeof value !== 'number' || !Number.isSafeInteger(value) || value < 0) {
      throw new Error('图片坐标/尺寸必须为非负整数');
    }
    return value;
  }

  static byteSize(width: number, height: number): number {
    ImageScriptBridge.integer(width);
    ImageScriptBridge.integer(height);
    const size = width * height * 4;
    if (!Number.isSafeInteger(size) || size > ImageScriptBridge.LIMIT) {
      throw new Error('图片超过变换内存上限');
    }
    return size;
  }

  private static put(surface: ImageSurface): number {
    const size = ImageScriptBridge.byteSize(surface.width, surface.height);
    if (surface.bytes.byteLength !== size || ImageScriptBridge.allocated + size > ImageScriptBridge.LIMIT) {
      throw new Error('图片数据长度不匹配或会话内存已满');
    }
    const key = ImageScriptBridge.nextKey++;
    ImageScriptBridge.images.set(key, surface);
    ImageScriptBridge.allocated += size;
    Log.audit(ImageScriptBridge.trace, '图片句柄创建', `句柄=${key}；尺寸=${surface.width}x${surface.height}；累计字节=${ImageScriptBridge.allocated}`);
    return key;
  }

  private static empty(width: number, height: number): ImageSurface {
    const size = ImageScriptBridge.byteSize(width, height);
    if (ImageScriptBridge.allocated + size > ImageScriptBridge.LIMIT) { throw new Error('图片会话内存已满'); }
    return new ImageSurface(width, height, new Uint8Array(size));
  }

  private static bounds(surface: ImageSurface, x: number, y: number, width: number, height: number): void {
    if (x + width > surface.width || y + height > surface.height) { throw new Error('图片矩形超出边界，未裁切或写入'); }
  }

  private static copy(dst: ImageSurface, x: number, y: number, src: ImageSurface,
    sx: number, sy: number, width: number, height: number): void {
    ImageScriptBridge.bounds(dst, x, y, width, height);
    ImageScriptBridge.bounds(src, sx, sy, width, height);
    // Preserve original row-by-row semantics, including self-copy.
    for (let row = 0; row < height; row++) {
      if (dst !== src) {
        const from = ((sy + row) * src.width + sx) * 4;
        const to = ((y + row) * dst.width + x) * 4;
        dst.bytes.set(src.bytes.subarray(from, from + width * 4), to);
        continue;
      }
      for (let col = 0; col < width; col++) {
        const from = ((sy + row) * src.width + sx + col) * 4;
        const to = ((y + row) * dst.width + x + col) * 4;
        for (let channel = 0; channel < 4; channel++) { dst.bytes[to + channel] = src.bytes[from + channel]; }
      }
    }
  }

  static handle(record: Record<string, Object>): Object | null {
    const op = String(record['function'] ?? '');
    if (ImageScriptBridge.trace.length === 0) {
      Log.audit('image-outside-session', '图片桥拒绝', `操作=${op}；不在modifyImage会话内，未分配内存`);
      return null;
    }
    const trace = ImageScriptBridge.trace;
    Log.audit(trace, '图片桥请求', `操作=${op}`);
    try {
      const width = (): number => ImageScriptBridge.integer(record['width']);
      const height = (): number => ImageScriptBridge.integer(record['height']);
      let value: Object | null = null;
      if (op === 'emptyImage') {
        value = ImageScriptBridge.put(ImageScriptBridge.empty(width(), height()));
      } else {
        const key = ImageScriptBridge.integer(record['key']);
        const src = ImageScriptBridge.images.get(key);
        if (src === undefined) { throw new Error('图片句柄已过期或不属于本次会话'); }
        if (op === 'getWidth') { value = src.width; }
        else if (op === 'getHeight') { value = src.height; }
        else if (op === 'copyAndRotate90') {
          const rotated = ImageScriptBridge.empty(src.height, src.width);
          for (let y = 0; y < src.height; y++) {
            for (let x = 0; x < src.width; x++) {
              const from = (y * src.width + x) * 4;
              const to = (x * src.height + src.height - y - 1) * 4;
              for (let c = 0; c < 4; c++) { rotated.bytes[to + c] = src.bytes[from + c]; }
            }
          }
          value = ImageScriptBridge.put(rotated);
        } else if (op === 'copyRange') {
          const x = ImageScriptBridge.integer(record['x']);
          const y = ImageScriptBridge.integer(record['y']);
          const w = width();
          const h = height();
          ImageScriptBridge.bounds(src, x, y, w, h);
          const cropped = ImageScriptBridge.empty(w, h);
          ImageScriptBridge.copy(cropped, 0, 0, src, x, y, w, h);
          value = ImageScriptBridge.put(cropped);
        } else if (op === 'fillImageAt' || op === 'fillImageRangeAt') {
          const other = ImageScriptBridge.result(ImageScriptBridge.integer(record['image']));
          ImageScriptBridge.copy(src, ImageScriptBridge.integer(record['x']), ImageScriptBridge.integer(record['y']),
            other, op === 'fillImageAt' ? 0 : ImageScriptBridge.integer(record['srcX']),
            op === 'fillImageAt' ? 0 : ImageScriptBridge.integer(record['srcY']),
            op === 'fillImageAt' ? other.width : width(), op === 'fillImageAt' ? other.height : height());
        } else { throw new Error('未知图片操作'); }
      }
      Log.audit(trace, '图片桥返回', `操作=${op}；结果=${value === null ? '已写入/void' : value}`);
      return value;
    } catch (error) {
      Log.audit(trace, '图片桥拒绝/异常', `操作=${op}；原因=${String(error)}；未返回成功`);
      throw new Error(String(error));
    }
  }
}
