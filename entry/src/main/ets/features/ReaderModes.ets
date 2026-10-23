/**
 * Reader mode helpers.
 *
 * Dart original: lib/features/reader/reader_page.dart `enum ReaderMode` and
 * lib/features/reader/reader_mode_labels.dart. Kept free of ArkUI/database
 * imports so the index mapping can be tested without a device.
 */

/** Upstream order, used for the mode cycle in the reader top bar. */
export const READER_MODES: string[] = [
  'galleryRightToLeft',
  'galleryLeftToRight',
  'galleryTopToBottom',
  'continuousTopToBottom',
  'waterfallTopToBottom',
  'continuousLeftToRight',
  'continuousRightToLeft'
];

/** Current chapter position; `index` is -1 when the chapter is unknown. */
export class ChapterInfo {
  index: number = -1;
  total: number = 0;
}

export class ReaderModes {
  static readonly fallback: string = 'waterfallTopToBottom';

  /** Mirrors `ReaderMode.fromKey`, which falls back to waterfall. */
  static normalize(key: string): string {
    return READER_MODES.indexOf(key) >= 0 ? key : ReaderModes.fallback;
  }

  static isGallery(key: string): boolean {
    return key.startsWith('gallery');
  }

  static isWaterfall(key: string): boolean {
    return key.startsWith('waterfall');
  }

  static isContinuous(key: string): boolean {
    return key.startsWith('continuous') || ReaderModes.isWaterfall(key);
  }

  /** Gallery modes page vertically; continuous/waterfall scroll vertically. */
  static isVertical(key: string): boolean {
    return key === 'galleryTopToBottom' || key === 'continuousTopToBottom' ||
      ReaderModes.isWaterfall(key);
  }

  /**
   * Upstream reverses the image list for right-to-left modes
   * (`images = images.reversed.toList()`), so display order and stored page
   * numbers are opposite for exactly these two modes.
   */
  static isReversed(key: string): boolean {
    return key === 'galleryRightToLeft' || key === 'continuousRightToLeft';
  }

  static label(key: string): string {
    switch (ReaderModes.normalize(key)) {
      case 'galleryRightToLeft':
        return '翻页（右→左）';
      case 'galleryLeftToRight':
        return '翻页（左→右）';
      case 'galleryTopToBottom':
        return '翻页（上→下）';
      case 'continuousTopToBottom':
        return '连续（上→下）';
      case 'waterfallTopToBottom':
        return '瀑布流（上→下）';
      case 'continuousLeftToRight':
        return '连续（左→右）';
      default:
        return '连续（右→左）';
    }
  }

  static nextMode(key: string): string {
    const index = READER_MODES.indexOf(ReaderModes.normalize(key));
    return READER_MODES[(index + 1) % READER_MODES.length];
  }

  /** Actual (1-based page order) index -> position in the rendered list. */
  static toDisplayIndex(key: string, actualIndex: number, count: number): number {
    if (count <= 0) {
      return 0;
    }
    const clamped = Math.min(Math.max(actualIndex, 0), count - 1);
    return ReaderModes.isReversed(key) ? count - 1 - clamped : clamped;
  }

  /** Position in the rendered list -> actual index. Symmetric to the above. */
  static toActualIndex(key: string, displayIndex: number, count: number): number {
    return ReaderModes.toDisplayIndex(key, displayIndex, count);
  }

  /** Rendered order of the page urls for the current mode. */
  static displayOrder(key: string, images: string[]): string[] {
    return ReaderModes.isReversed(key) ? images.slice().reverse() : images.slice();
  }
}
