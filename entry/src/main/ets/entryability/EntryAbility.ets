import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { AppContext } from '../foundation/AppContext';
import { Log } from '../foundation/Log';
import { DownloadQueue } from '../features/DownloadQueue';

const DOMAIN = 0x0000;
/** Same canvas colour as UiTheme.page; drawn behind the transparent system bars. */
const WINDOW_BACKGROUND = '#F4F5F8';
const BAR_CONTENT_COLOR = '#171A21';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      // The UI ships light-only colours. Following the system dark theme made
      // system-styled popups (Select menus, dialogs) render light text on our
      // light surfaces, which is unreadable, so pin the app to light mode.
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
    } catch (err) {
      hilog.error(DOMAIN, 'VenHM', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    AppContext.init(this.context);
    Log.info('EntryAbility', 'onCreate');
  }

  /**
   * Draw the app behind the status/navigation bars so no contrasting strip is
   * left above or below the content, while keeping the bars visible (dark icons
   * on the app canvas). The reader additionally hides both bars while open.
   */
  private applyImmersiveLayout(windowStage: window.WindowStage): void {
    try {
      const main = windowStage.getMainWindowSync();
      main.setWindowLayoutFullScreen(true).catch((error: Object) => {
        Log.warn('EntryAbility', `layout fullscreen unavailable: ${error}`);
      });
      main.setWindowBackgroundColor(WINDOW_BACKGROUND);
      main.setWindowSystemBarProperties({
        statusBarColor: '#00000000',
        navigationBarColor: '#00000000',
        statusBarContentColor: BAR_CONTENT_COLOR,
        navigationBarContentColor: BAR_CONTENT_COLOR
      }).catch((error: Object) => {
        Log.warn('EntryAbility', `system bar styling unavailable: ${error}`);
      });
    } catch (error) {
      // A platform that refuses this still gets a fully usable inset window.
      Log.warn('EntryAbility', `immersive layout unavailable: ${error}`);
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    this.applyImmersiveLayout(windowStage);
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'VenHM', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
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
