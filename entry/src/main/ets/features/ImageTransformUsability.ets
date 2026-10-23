import { image } from '@kit.ImageKit';
import { ImageTransforms } from '../network/ImageTransforms';
import { Log } from '../foundation/Log';

/** Real ImageKit + QuickJS pixel oracle, no downloads or user data touched. */
export class ImageTransformUsability {
  static async run(): Promise<void> {
    const trace = `image-pixel-probe-${Date.now()}`;
    const raw = new ArrayBuffer(3 * 5 * 4);
    const rows = [11, 22, 33, 44, 55];
    const rgba = new Uint8Array(raw);
    for (let y = 0; y < 5; y++) {
      for (let x = 0; x < 3; x++) {
        const i = (y * 3 + x) * 4;
        rgba[i] = rows[y]; rgba[i + 1] = x * 30; rgba[i + 2] = 99; rgba[i + 3] = 255;
      }
    }
    Log.audit(trace, '像素验收到达', '3×5不对称像素；2分块带余数；旋转/裁剪/填充；无用户数据');
    const source = await image.createPixelMap(raw, { size: { width: 3, height: 5 },
      pixelFormat: image.PixelMapFormat.RGBA_8888, srcPixelFormat: image.PixelMapFormat.RGBA_8888,
      alphaType: image.AlphaType.UNPREMUL });
    const packer = image.createImagePacker();
    let input: ArrayBuffer;
    try { input = await packer.packToData(source, { format: 'image/png', quality: 100 }); }
    finally { await packer.release(); await source.release(); }
    const script = 'let modifyImage = image => { let out=Image.empty(image.width,image.height);' +
      'out.fillImageRangeAt(0,0,image,0,2,image.width,3);' +
      'out.fillImageRangeAt(0,3,image,0,0,image.width,2);return out; };';
    const output = await ImageTransforms.apply(input, script, trace);
    await ImageTransformUsability.check(output, 3, 5, [33, 44, 55, 11, 22], trace);
    const rotated = await ImageTransforms.apply(input,
      'let modifyImage = image => { const copy=image.copyRange(0,0,3,5);' +
      'let out=Image.empty(5,3);out.fillImageAt(0,0,copy.copyAndRotate90());return out; };', trace);
    const decoder = image.createImageSource(rotated);
    const pixel = await decoder.createPixelMap({ desiredPixelFormat: image.PixelMapFormat.RGBA_8888 });
    try {
      const info = await pixel.getImageInfo();
      const buffer = new ArrayBuffer(60);
      await pixel.readPixelsToBuffer(buffer);
      const values = new Uint8Array(buffer);
      if (info.size.width !== 5 || info.size.height !== 3) { throw new Error('旋转尺寸不符'); }
      for (let y = 0; y < 3; y++) {
        for (let x = 0; x < 5; x++) {
          const i = (y * 5 + x) * 4;
          if (values[i] !== rows[4 - x] || values[i + 1] !== y * 30 ||
              values[i + 2] !== 99 || values[i + 3] !== 255) { throw new Error('旋转逐像素不符'); }
        }
      }
    } finally { await pixel.release(); await decoder.release(); }
    let rejected = false;
    try { await ImageTransforms.apply(input, 'let modifyImage=i=>i.copyRange(3,0,1,1);', trace); }
    catch (error) { rejected = true; }
    if (!rejected) { throw new Error('越界图片裁剪未拒绝'); }
    // Exception must release the slot and all handles for the following valid request.
    await ImageTransformUsability.check(await ImageTransforms.apply(input, script, trace), 3, 5,
      [33, 44, 55, 11, 22], trace);
    Log.audit(trace, '像素验收返回', 'PASS · 重排带余数、RGBA四通道、裁剪、顺时针旋转、填充、异常后恢复；非JM真实内容验收');
    Log.info('ImageTransformUsability', 'PASS · ImageKit/QuickJS pixel oracle (reorder remainder/rotate/crop/fill/reject/recover)');
  }

  private static async check(bytes: ArrayBuffer, width: number, height: number, rows: number[], trace: string): Promise<void> {
    const decoder = image.createImageSource(bytes);
    const pixel = await decoder.createPixelMap({ desiredPixelFormat: image.PixelMapFormat.RGBA_8888 });
    try {
      const info = await pixel.getImageInfo();
      if (info.size.width !== width || info.size.height !== height) { throw new Error('像素重排尺寸不符'); }
      const buffer = new ArrayBuffer(width * height * 4);
      await pixel.readPixelsToBuffer(buffer);
      const values = new Uint8Array(buffer);
      for (let y = 0; y < height; y++) {
        for (let x = 0; x < width; x++) {
          const i = (y * width + x) * 4;
          if (values[i] !== rows[y] || values[i + 1] !== x * 30 || values[i + 2] !== 99 || values[i + 3] !== 255) {
            throw new Error(`逐像素不符 x=${x} y=${y}`);
          }
        }
      }
      Log.audit(trace, '像素比对', `逐像素${width}x${height}×4通道符合固定预期`);
    } finally { await pixel.release(); await decoder.release(); }
  }
}
