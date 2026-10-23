import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { AppContext } from '../foundation/AppContext';
import { Log } from '../foundation/Log';
import { DownloadQueue } from '../features/DownloadQueue';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'VeneraHM', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    AppContext.init(this.context);
    Log.info('EntryAbility', 'onCreate');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'VeneraHM', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      Log.info('EntryAbility', 'content loaded');
    });
  }

  onWindowStageDestroy(): void {
    Log.info('EntryAbility', 'onWindowStageDestroy');
  }

  onForeground(): void {
    // Async now: it may acquire/release the native background-transfer lease.
    DownloadQueue.setForeground(true).catch((error: Object) => {
      Log.warn('EntryAbility', `foreground download state failed: ${error}`);
    });
    Log.info('EntryAbility', 'onForeground');
  }

  onBackground(): void {
    // Without an accepted DATA_TRANSFER lease this pauses; it never resumes by itself.
    DownloadQueue.setForeground(false).catch((error: Object) => {
      Log.warn('EntryAbility', `background download state failed: ${error}`);
    });
    Log.info('EntryAbility', 'onBackground');
  }

  onDestroy(): void {
    Log.info('EntryAbility', 'onDestroy');
    DownloadQueue.shutdown('UIAbility 销毁').catch((error: Object) => {
      Log.warn('EntryAbility', `download shutdown failed: ${error}`);
    });
  }

  /** Notification tap opens the download list; it must never auto-resume tasks. */
  private routeFromWant(want: Want): void {
    if (want?.parameters?.['openDownloads'] !== true) { return; }
    router.pushUrl({ url: 'pages/DownloadsPage' }).catch((error: Object) => {
      Log.warn('EntryAbility', `open downloads failed: ${error}`);
    });
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.routeFromWant(want);
  }
}
