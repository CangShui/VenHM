/** Pure reader tap policy. Inputs are local image/spread viewport fractions, never screen coordinates. */
export class ReaderTapPolicy {
  static readonly delayMs: number = 200;
  static readonly sideFraction: number = 0.3;

  static normalizeX(localX: number, width: number): number {
    if (!Number.isFinite(localX) || !Number.isFinite(width) || width <= 0 || localX < 0 || localX > width) {
      return -1;
    }
    return localX / width;
  }

  /** Horizontal gallery images occupy equal slots in the image viewport. */
  static spreadX(imageX: number, slot: number, count: number): number {
    if (!Number.isFinite(imageX) || imageX < 0 || imageX > 1 || !Number.isFinite(slot) ||
      !Number.isFinite(count) || Math.floor(slot) !== slot || Math.floor(count) !== count ||
      count < 1 || slot < 0 || slot >= count) { return -1; }
    return (slot + imageX) / count;
  }

  /** Source-order step: RTL left=next/right=previous; vertical modes retain requested LEFT/RIGHT affordance. */
  static step(mode: string, normalizedX: number, enabled: boolean, reverse: boolean): number {
    if (!enabled || !Number.isFinite(normalizedX) || normalizedX < 0 || normalizedX > 1) { return 0; }
    let direction: number = 0;
    if (normalizedX < ReaderTapPolicy.sideFraction) { direction = -1; }
    else if (normalizedX > 1 - ReaderTapPolicy.sideFraction) { direction = 1; }
    // No center action is specified: do not turn a page or toggle the toolbar.
    if (direction === 0) { return 0; }
    if (mode === 'galleryRightToLeft' || mode === 'continuousRightToLeft') { direction = -direction; }
    return reverse ? -direction : direction;
  }
}
