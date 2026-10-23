/** One producer cancellation signal; consumers are reference-counted separately. */
export class RequestCancellation {
  private stopped: boolean = false;
  private sequence: number = 0;
  private listeners: Map<number, () => void> = new Map<number, () => void>();
  get cancelled(): boolean { return this.stopped; }
  subscribe(listener: () => void): number {
    if (this.stopped) { listener(); return 0; }
    const id = ++this.sequence; this.listeners.set(id, listener); return id;
  }
  unsubscribe(id: number): void { if (id !== 0) { this.listeners.delete(id); } }
  cancel(): void {
    if (this.stopped) { return; }
    this.stopped = true;
    const current = Array.from(this.listeners.values()); this.listeners.clear();
    for (const listener of current) { listener(); }
  }
}
