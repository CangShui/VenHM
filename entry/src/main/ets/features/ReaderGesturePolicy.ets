/** Configurable reader-only regions; leaves pinch/pan/double tap inside AsyncComicImage intact. */
export class ReaderGesturePolicy {
  static step(mode: string, x: number, enabled: boolean, reverse: boolean, edgePercent: number): number {
    if (!enabled || !Number.isFinite(x) || x < 0 || x > 1) { return 0; }
    const edge = Math.max(10, Math.min(45, edgePercent)) / 100;
    let result = x < edge ? -1 : x > 1 - edge ? 1 : 0;
    if (mode === 'galleryRightToLeft' || mode === 'continuousRightToLeft') { result = -result; }
    return reverse ? -result : result;
  }
  static center(x: number, edgePercent: number): boolean {
    const edge = Math.max(10, Math.min(45, edgePercent)) / 100;
    return Number.isFinite(x) && x >= edge && x <= 1 - edge;
  }
}
