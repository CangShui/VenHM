/**
 * Change signal for the sandbox local-comic library.
 *
 * Home and the bookshelf cache the `local_comics` listing. Deleting a download
 * task removes its folder, so those cached lists must be refreshed instead of
 * staying stale until the process restarts. This is a UI-level notification
 * only: it carries no data and never triggers network or database work.
 */
export class LocalLibrarySignal {
  private static listeners: Array<() => void> = [];

  static addListener(listener: () => void): void {
    if (LocalLibrarySignal.listeners.indexOf(listener) < 0) {
      LocalLibrarySignal.listeners.push(listener);
    }
  }

  static removeListener(listener: () => void): void {
    const index = LocalLibrarySignal.listeners.indexOf(listener);
    if (index >= 0) {
      LocalLibrarySignal.listeners.splice(index, 1);
    }
  }

  /** One failing listener must not stop the others from refreshing. */
  static notify(): void {
    const snapshot = LocalLibrarySignal.listeners.slice();
    for (let i = 0; i < snapshot.length; i++) {
      try { snapshot[i](); } catch (error) { /* listener reloads handle their own errors */ }
    }
  }
}
