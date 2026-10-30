/** Lightweight lifecycle signal only: no UI state, logging, timers or disk access. */
export class ReaderWorkload {
  private static readonly visibleOwners: Set<string> = new Set<string>();

  /** Idempotent per owner. A reader instance must use the same stable owner on enter and leave. */
  static setReaderVisible(visible: boolean, owner: string = 'reader'): void {
    if (visible) { ReaderWorkload.visibleOwners.add(owner); }
    else { ReaderWorkload.visibleOwners.delete(owner); }
  }

  static isReaderVisible(): boolean {
    return ReaderWorkload.visibleOwners.size > 0;
  }
}
