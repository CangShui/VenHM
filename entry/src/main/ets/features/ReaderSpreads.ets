/** Pure source-image/spread mapping. No URLs, ArkUI, persistence or image decoding. */
export class ReaderSpread {
  index: number = 0;
  start: number = 0;
  end: number = 0;
  imageIndices: number[] = [];
}

export class ReaderSpreads {
  static perScreen(portrait: number, landscape: number, isLandscape: boolean): number {
    const value = isLandscape ? landscape : portrait;
    return Number.isFinite(value) ? Math.max(1, Math.min(5, Math.floor(value))) : 1;
  }

  static create(count: number, perScreen: number, firstAlone: boolean, rtl: boolean = false): ReaderSpread[] {
    const result: ReaderSpread[] = [];
    const size = ReaderSpreads.perScreen(perScreen, perScreen, false);
    const total = Number.isFinite(count) ? Math.max(0, Math.floor(count)) : 0;
    let start = 0;
    while (start < total) {
      const spread = new ReaderSpread();
      spread.index = result.length;
      spread.start = start;
      spread.end = Math.min(total, start + (firstAlone && start === 0 ? 1 : size));
      for (let image = spread.start; image < spread.end; image++) {
        spread.imageIndices.push(image);
      }
      if (rtl) { spread.imageIndices.reverse(); }
      result.push(spread);
      start = spread.end;
    }
    return rtl ? result.reverse() : result;
  }

  static sourceToDisplay(source: number, count: number, size: number, firstAlone: boolean,
    rtl: boolean = false): number {
    const total = Number.isFinite(count) ? Math.max(0, Math.floor(count)) : 0;
    if (total === 0) { return 0; }
    const per = ReaderSpreads.perScreen(size, size, false);
    const image = Number.isFinite(source) ? Math.max(0, Math.min(total - 1, Math.floor(source))) : 0;
    const index = firstAlone ? (image === 0 ? 0 : 1 + Math.floor((image - 1) / per)) : Math.floor(image / per);
    const groups = firstAlone ? 1 + Math.ceil((total - 1) / per) : Math.ceil(total / per);
    return rtl ? groups - 1 - index : index;
  }

  static displayToSource(display: number, count: number, size: number, firstAlone: boolean,
    rtl: boolean = false): number {
    const total = Number.isFinite(count) ? Math.max(0, Math.floor(count)) : 0;
    const per = ReaderSpreads.perScreen(size, size, false);
    const groups = total === 0 ? 0 : firstAlone ? 1 + Math.ceil((total - 1) / per) : Math.ceil(total / per);
    if (!Number.isFinite(display) || Math.floor(display) !== display || display < 0 || display >= groups) { return -1; }
    const index = rtl ? groups - 1 - display : display;
    return firstAlone ? (index === 0 ? 0 : 1 + (index - 1) * per) : index * per;
  }

  /** Advance whole groups in SOURCE order, never repeat an image inside one group. */
  static nextSource(source: number, count: number, size: number, firstAlone: boolean, offset: number): number {
    const next = ReaderSpreads.sourceToDisplay(source, count, size, firstAlone) + offset;
    return ReaderSpreads.displayToSource(next, count, size, firstAlone);
  }

  static pageCounter(source: number, count: number, size: number, firstAlone: boolean): string {
    const total = Number.isFinite(count) ? Math.max(0, Math.floor(count)) : 0;
    if (total === 0) { return '— / —'; }
    const start = ReaderSpreads.displayToSource(ReaderSpreads.sourceToDisplay(source, total, size, firstAlone),
      total, size, firstAlone);
    const end = Math.min(total, start + (firstAlone && start === 0 ? 1 : ReaderSpreads.perScreen(size, size, false)));
    const range = end - start === 1 ? `${start + 1}` : `${start + 1}–${end}`;
    return `${range} / ${total}`;
  }
}
