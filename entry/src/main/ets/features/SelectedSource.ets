import { Settings } from '../foundation/Settings';
import { promptAction } from '@kit.ArkUI';
import { SourceManager } from '../source/SourceManager';
import { Log } from '../foundation/Log';

/** One stable source identity for discovery tabs, independent of capabilities/order. */
export class SelectedSource {
  private static key: string = '';
  private static initialized: boolean = false;
  private static listeners: Map<number, (key: string) => void> = new Map<number, (key: string) => void>();
  private static nextListener: number = 0;
  private static writes: Promise<void> = Promise.resolve();

  /** Call after AppInit. Preserve even a removed source, rather than silently switch. */
  static initialize(): string {
    if (!SelectedSource.initialized) {
      SelectedSource.key = Settings.getString('selectedSourceKey', '');
      SelectedSource.initialized = true;
    }
    if (SelectedSource.key.length === 0) {
      const sources = SourceManager.all();
      if (sources.length > 0) { SelectedSource.select(sources[0].key); }
    }
    return SelectedSource.key;
  }

  static current(): string { return SelectedSource.key; }

  static subscribe(listener: (key: string) => void): number {
    const id = ++SelectedSource.nextListener;
    SelectedSource.listeners.set(id, listener);
    return id;
  }

  static unsubscribe(id: number): void { SelectedSource.listeners.delete(id); }

  /** Publish synchronously; serialize writes so rapid selection cannot persist an older key. */
  static select(key: string): void {
    if (key.length === 0) { return; }
    SelectedSource.key = key;
    // Re-selecting the same real source is also an explicit user action. Search
    // may currently be in aggregate mode; it must follow that real-source pick.
    for (const listener of SelectedSource.listeners.values()) {
      try { listener(key); }
      catch (error) { Log.audit('selected-source', '选源通知异常', '单个界面通知失败；其余界面与持久化继续，不记录异常内容'); }
    }
    SelectedSource.writes = SelectedSource.writes.then(async () => {
      await Settings.setString('selectedSourceKey', key);
    }).catch((error: Object) => {
      Log.audit('selected-source', '选择保存异常', '偏好保存失败；当前会话选择保留；重启前请重选；不记录异常正文');
      promptAction.showToast({ message: '源选择保存失败，当前选择仅本次会话有效，请重新选择' });
    });
  }
}
