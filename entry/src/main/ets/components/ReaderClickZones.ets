/**
 * Reading-window interaction policy, independently implemented from the default
 * behavior documented in Luoyacheng/legado-E at 8b87c5aba4df91c39a3a0939a68a1180b9f2ee1c.
 * Reference: AppConfig.kt:38-46, ReadView.kt:132-146,393-445.
 * No Android source/UI assets are embedded. Coordinates are fractions of the
 * WHOLE visible reading viewport, not an individual picture or decoded bitmap.
 */
export class ReaderClickZones {
  static action(x: number, y: number, pageTurns: boolean, rtl: boolean, reverse: boolean): string {
    if (!Number.isFinite(x) || !Number.isFinite(y) || x < 0 || y < 0 || x >= 1 || y >= 1) { return 'none'; }
    const column = x < 0.33 ? 0 : x < 0.66 ? 1 : 2;
    const row = y < 0.33 ? 0 : y < 0.66 ? 1 : 2;
    if (row === 1 && column === 1) { return 'menu'; }
    if (!pageTurns) { return 'none'; }
    // Mirror side columns for manga RTL without reversing the vertical center
    // column's top=previous/bottom=next affordance. Explicit reverse flips turns.
    const logicalColumn = rtl ? 2 - column : column;
    let next = logicalColumn === 2 || (logicalColumn === 1 && row === 2);
    if (reverse) { next = !next; }
    return next ? 'next' : 'previous';
  }
}

/** Single-contact tap arbitration leaves native swipe/pinch/double-tap intact. */
export class ReaderCanvasGesture {
  // Our comic reader keeps native double-tap zoom (unlike the reference's
  // text tap dispatcher), so wait beyond the normal 300ms double-tap interval.
  static readonly delayMs: number = 350;
  private down: boolean = false;
  private rejected: boolean = false;
  private startX: number = 0;
  private startY: number = 0;
  private started: number = 0;
  private lastUp: number = -10000;
  private lastX: number = 0;
  private lastY: number = 0;

  begin(x: number, y: number, time: number, count: number): void {
    const valid = Number.isFinite(x) && Number.isFinite(y) && Number.isFinite(time);
    const dx = x - this.lastX; const dy = y - this.lastY;
    const doubleTap = time >= this.lastUp && time - this.lastUp <= ReaderCanvasGesture.delayMs &&
      dx * dx + dy * dy < 60 * 60;
    this.down = valid;
    this.rejected = !valid || count !== 1 || doubleTap;
    this.startX = x; this.startY = y; this.started = time;
  }

  move(x: number, y: number, count: number): void {
    if (!this.down || count !== 1 || !Number.isFinite(x) || !Number.isFinite(y) ||
      Math.abs(x - this.startX) > 8 || Math.abs(y - this.startY) > 8) { this.rejected = true; }
  }

  end(x: number, y: number, time: number, remaining: number): boolean {
    this.move(x, y, 1);
    const isTap = this.down && !this.rejected && remaining === 0 && Number.isFinite(time) &&
      time >= this.started && time - this.started < 500;
    this.down = false;
    // Keep a recent completed contact even when rejected as tap2 so a rapid
    // third contact cannot resurrect the first delayed menu/page action.
    this.lastUp = time; this.lastX = x; this.lastY = y;
    return isTap;
  }

  get downX(): number { return this.startX; }
  get downY(): number { return this.startY; }

  cancel(): void { this.down = false; this.rejected = true; }
}
