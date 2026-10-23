import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';

/** Safe to log phase/code; deliberately excludes the SDK error and request data. */
export class ReaderWindowChromeError extends Error {
  readonly phase: string;
  readonly code: string;
  readonly restorePending: boolean;

  constructor(phase: string, code: string, restorePending: boolean) {
    super(`ReaderWindowChrome ${phase} ${code}`);
    this.name = 'ReaderWindowChromeError';
    this.phase = phase;
    this.code = code;
    this.restorePending = restorePending;
  }
}

class ReaderWindowSnapshot {
  readonly target: window.Window;
  readonly layoutFullScreen: boolean;
  readonly bars: Array<'status' | 'navigation'>;

  constructor(target: window.Window, layoutFullScreen: boolean, bars: Array<'status' | 'navigation'>) {
    this.target = target;
    this.layoutFullScreen = layoutFullScreen;
    this.bars = bars;
  }
}

/**
 * One reader-page instance owns one helper. No app initialization, persistence,
 * theme, bar colors/contrast, permissions, or process-global window state.
 *
 * API 21 has no public getter for enabled status/navigation bar names:
 * getWindowSystemBarProperties/getStatusBarProperty describe style, not visibility.
 * Snapshot isFullScreen first (both bars already hidden); otherwise infer visible
 * bars from TYPE_SYSTEM and TYPE_NAVIGATION_INDICATOR avoid areas. All-zero areas
 * on a non-fullscreen window are ambiguous: ONLY for this app's normal-window
 * baseline, fall back to both normal bars. Geometry inference is not an exact
 * visibility API (e.g. transient bars or a platform reporting empty avoid areas).
 *
 * Call enter on show/appear, leave on hide/disappear/route exit; catch both
 * Promises. leave resolves only after all earlier setters and restoration settle.
 * A rejected restoration retains the SAME window/snapshot; explicitly call leave
 * again to retry. A later enter must also restore that snapshot before acquiring
 * any new window. No timeout is used: an uncancellable SDK setter must settle
 * before another setting can safely run. Keep this instance until cleanup ends.
 */
export class ReaderWindowChrome {
  private epoch: number = 0;
  private active: boolean = false;
  private tail: Promise<void> = Promise.resolve();
  private entering: Promise<void> | undefined = undefined;
  private leaving: Promise<void> | undefined = undefined;
  private owned: ReaderWindowSnapshot | undefined = undefined;

  enter(context: common.Context): Promise<void> {
    if (this.active) {
      return this.entering ?? this.tail;
    }
    this.active = true;
    const epoch = ++this.epoch;
    const operation = this.tail.then(async (): Promise<void> => {
      try {
        await this.enterOwned(context, epoch);
      } catch (error) {
        if (this.isCurrent(epoch)) {
          this.active = false;
        }
        if (error instanceof ReaderWindowChromeError) { throw error; }
        throw new ReaderWindowChromeError('enter', 'WINDOW_STATE_ENTER_FAILED', this.owned !== undefined);
      }
    });
    this.entering = operation;
    // The queue survives rejection, while callers still receive the real failure.
    this.tail = operation.then((): void => {}, (): void => {});
    return operation;
  }

  leave(): Promise<void> {
    if (!this.active && this.leaving !== undefined) {
      return this.leaving;
    }
    // Invalidate synchronously, even while getLastWindow/a setter is awaiting.
    this.active = false;
    ++this.epoch;
    const operation = this.tail.then((): Promise<void> => this.restoreOwned());
    this.leaving = operation;
    this.tail = operation.then((): void => {
      if (this.leaving === operation) {
        this.leaving = undefined;
      }
    }, (): void => {
      if (this.leaving === operation) {
        this.leaving = undefined;
      }
    });
    return operation;
  }

  private isCurrent(epoch: number): boolean {
    return this.active && this.epoch === epoch;
  }

  private hasGeometry(area: window.AvoidArea): boolean {
    return area.topRect.height > 0 || area.topRect.width > 0 ||
      area.bottomRect.height > 0 || area.bottomRect.width > 0 ||
      area.leftRect.height > 0 || area.leftRect.width > 0 ||
      area.rightRect.height > 0 || area.rightRect.width > 0;
  }

  private snapshot(target: window.Window): ReaderWindowSnapshot {
    const properties = target.getWindowProperties();
    // Copy the boolean before ANY layout or system-bar mutation.
    const layout = properties.isLayoutFullScreen;
    const bars: Array<'status' | 'navigation'> = [];
    if (!properties.isFullScreen) {
      // A getter failure refuses entry; it is not treated as the all-zero case.
      const system = target.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const indicator = target.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      if (system.topRect.height > 0) {
        bars.push('status');
      }
      if (system.bottomRect.height > 0 || system.leftRect.width > 0 || system.rightRect.width > 0 ||
        this.hasGeometry(indicator)) {
        bars.push('navigation');
      }
      if (!this.hasGeometry(system) && !this.hasGeometry(indicator)) {
        // App-specific baseline, NOT a claim that API 21 can read bar visibility.
        bars.push('status');
        bars.push('navigation');
      }
    }
    return new ReaderWindowSnapshot(target, layout, bars);
  }

  private async enterOwned(context: common.Context, epoch: number): Promise<void> {
    if (!this.isCurrent(epoch)) {
      return;
    }
    // Do not overwrite a failed restoration with a newer window's snapshot.
    await this.restoreOwned();
    if (!this.isCurrent(epoch)) {
      return;
    }
    let target: window.Window;
    try {
      target = await window.getLastWindow(context);
    } catch (error) {
      throw new ReaderWindowChromeError('acquire', 'WINDOW_ACQUIRE_FAILED', false);
    }
    if (!this.isCurrent(epoch)) {
      return;
    }
    let snapshot: ReaderWindowSnapshot;
    try {
      snapshot = this.snapshot(target);
    } catch (error) {
      throw new ReaderWindowChromeError('snapshot', 'WINDOW_SNAPSHOT_FAILED', false);
    }
    if (!this.isCurrent(epoch)) {
      return;
    }
    // Save BEFORE calling a setter: even rejection can follow a partial change.
    this.owned = snapshot;
    try {
      await target.setWindowLayoutFullScreen(true);
    } catch (error) {
      return this.rejectEntry('enter-layout', 'WINDOW_LAYOUT_ENTER_FAILED', epoch);
    }
    if (!this.isCurrent(epoch)) {
      // Do not issue a late hide-bars call after the reader has left.
      await this.restoreOwned();
      return;
    }
    try {
      // Layout fullscreen alone does NOT hide status/navigation bars.
      await target.setWindowSystemBarEnable([]);
    } catch (error) {
      return this.rejectEntry('enter-bars', 'WINDOW_BARS_ENTER_FAILED', epoch);
    }
    if (!this.isCurrent(epoch)) {
      await this.restoreOwned();
    }
  }

  private async rejectEntry(phase: string, code: string, epoch: number): Promise<void> {
    if (this.isCurrent(epoch)) {
      this.active = false;
    }
    try {
      await this.restoreOwned();
    } catch (error) {
      throw new ReaderWindowChromeError(phase, code, true);
    }
    throw new ReaderWindowChromeError(phase, code, false);
  }

  private async restoreOwned(): Promise<void> {
    const snapshot = this.owned;
    if (snapshot === undefined) {
      return;
    }
    let layoutFailed = false;
    let barsFailed = false;
    // Restore layout first and bar visibility LAST, even if layout fails. A
    // rejecting setter may have partially applied; retry both on explicit retry.
    try {
      await snapshot.target.setWindowLayoutFullScreen(snapshot.layoutFullScreen);
    } catch (error) {
      layoutFailed = true;
    }
    try {
      await snapshot.target.setWindowSystemBarEnable(snapshot.bars);
    } catch (error) {
      barsFailed = true;
    }
    if (layoutFailed || barsFailed) {
      const code = layoutFailed && barsFailed ? 'WINDOW_RESTORE_LAYOUT_AND_BARS_FAILED' :
        (layoutFailed ? 'WINDOW_RESTORE_LAYOUT_FAILED' : 'WINDOW_RESTORE_BARS_FAILED');
      throw new ReaderWindowChromeError('restore', code, true);
    }
    // Never look up another window during restore or discard a failed snapshot.
    this.owned = undefined;
  }
}
