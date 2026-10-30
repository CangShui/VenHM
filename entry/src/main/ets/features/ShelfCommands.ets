/**
 * Tiny UI command bus between the shared tab bar and the bookshelf tab. Both
 * live in the same page, but the bar cannot call into a sibling component, so
 * the "+" action is published here and the shelf subscribes while visible.
 * No persistence, no network and no reading statistics.
 */
export class ShelfCommands {
  private static readonly listeners: Array<() => void> = [];

  static addListener(listener: () => void): void {
    if (ShelfCommands.listeners.indexOf(listener) < 0) { ShelfCommands.listeners.push(listener); }
  }

  static removeListener(listener: () => void): void {
    const index = ShelfCommands.listeners.indexOf(listener);
    if (index >= 0) { ShelfCommands.listeners.splice(index, 1); }
  }

  /** Ask the visible shelf to open its new-folder editor. */
  static newFolder(): void {
    const snapshot = ShelfCommands.listeners.slice();
    for (let i = 0; i < snapshot.length; i++) {
      try { snapshot[i](); } catch (error) { /* a closed shelf ignores the command */ }
    }
  }
}
