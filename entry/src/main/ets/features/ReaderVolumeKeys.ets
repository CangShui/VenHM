import inputConsumer from '@ohos.multimodalInput.inputConsumer';
import { KeyEvent } from '@ohos.multimodalInput.keyEvent';
import { KeyCode } from '@ohos.multimodalInput.keyCode';

/** Public API16 foreground-focus key consumption, never an audio/volume observer. */
export class ReaderVolumeKeys {
  private active: boolean = false;
  private enabled: boolean = false;
  private registered: boolean = false;
  private upRegistered: boolean = false;
  private downRegistered: boolean = false;
  private turn: (offset: number) => void;
  private up: (event: KeyEvent) => void;
  private down: (event: KeyEvent) => void;
  constructor(turn: (offset: number) => void) {
    this.turn = turn;
    this.up = (event: KeyEvent): void => { this.dispatch(-1); };
    this.down = (event: KeyEvent): void => { this.dispatch(1); };
  }
  /** Return false when inactive/disabled so late callbacks cannot turn pages. */
  dispatch(offset: number): boolean {
    if (!this.active || !this.enabled || !this.registered || (offset !== -1 && offset !== 1)) { return false; }
    this.turn(offset); return true;
  }
  sync(active: boolean, enabled: boolean): void {
    this.active = active; this.enabled = enabled;
    if (!active || !enabled) { this.release(); return; }
    if (this.registered) { return; }
    try {
      inputConsumer.on('keyPressed', { key: KeyCode.KEYCODE_VOLUME_UP, action: 1, isRepeat: false }, this.up);
      this.upRegistered = true;
      inputConsumer.on('keyPressed', { key: KeyCode.KEYCODE_VOLUME_DOWN, action: 1, isRepeat: false }, this.down);
      this.downRegistered = true;
      this.registered = true;
    } catch (error) {
      // If the second registration fails, release the first too. No global off().
      this.release(); throw new Error('此设备不支持阅读器音量键消费，系统音量保持原样');
    }
  }
  release(): void {
    this.active = false;
    this.registered = false;
    // Exact callbacks only: never remove another page/service's subscription.
    let failed: boolean = false;
    if (this.upRegistered) {
      try { inputConsumer.off('keyPressed', this.up); this.upRegistered = false; } catch (error) { failed = true; }
    }
    if (this.downRegistered) {
      try { inputConsumer.off('keyPressed', this.down); this.downRegistered = false; } catch (error) { failed = true; }
    }
    if (failed) { throw new Error('阅读器音量键取消订阅失败；页面已禁用回调'); }
  }
}
