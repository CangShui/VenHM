/** Pure reader presentation geometry; no pixels copied or source identities changed.
 * Fixed upstream comic_image.dart: a wide source becomes one tall display image,
 * size=(width/2,height*2), with right half above left by default. Odd widths use
 * fractional source boundaries just like the original Canvas painter.
 */
export class ReaderImageRect {
  x: number = 0;
  y: number = 0;
  width: number = 0;
  height: number = 0;
  constructor(x: number, y: number, width: number, height: number) {
    this.x = x; this.y = y; this.width = width; this.height = height;
  }
}
export class ReaderImageLayout {
  static validSize(width: number, height: number): boolean {
    return Number.isFinite(width) && Number.isFinite(height) && width > 0 && height > 0;
  }
  static isWide(width: number, height: number): boolean {
    return ReaderImageLayout.validSize(width, height) && width > height;
  }
  static displayRatio(width: number, height: number, split: boolean): number {
    if (!ReaderImageLayout.validSize(width, height)) { throw new Error('阅读图片尺寸无效'); }
    return width / height / (split && ReaderImageLayout.isWide(width, height) ? 4 : 1);
  }
  static sourceRects(width: number, height: number, invert: boolean): ReaderImageRect[] {
    if (!ReaderImageLayout.validSize(width, height)) { throw new Error('阅读图片尺寸无效'); }
    if (!ReaderImageLayout.isWide(width, height)) { return [new ReaderImageRect(0, 0, width, height)]; }
    const half = width / 2;
    const left = new ReaderImageRect(0, 0, half, height);
    const right = new ReaderImageRect(half, 0, half, height);
    return invert ? [left, right] : [right, left];
  }
  /** Width of the clipped pane in viewport units; the texture is exactly 2x as wide. */
  static paneOffset(viewportWidth: number, top: boolean, invert: boolean): number {
    if (!Number.isFinite(viewportWidth) || viewportWidth < 0) { return 0; }
    const right = top !== invert;
    return right ? -viewportWidth : 0;
  }
}
