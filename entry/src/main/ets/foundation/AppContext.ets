import { common } from '@kit.AbilityKit';
import { Log } from './Log';

/**
 * Version reported to source scripts (`APP.version`) and compared against each
 * script's `minAppVersion`.
 *
 * Comic sources in venera-configs gate themselves on the *Venera* app version
 * (the highest declared minimum is 1.6.0). This port tracks VeneraNext 1.17.0,
 * so it advertises that version - reporting the app's own 1.0.0 would reject
 * almost every source.
 */
export const APP_VERSION: string = '1.17.0';

/**
 * Process-wide application context.
 *
 * Dart original: lib/foundation/app.dart held the global App state plus the
 * resolved data/cache directories. On HarmonyOS the equivalent handles come from
 * the UIAbilityContext, so EntryAbility registers it once in onCreate().
 */
export class AppContext {
  private static abilityContext: common.Context | undefined = undefined;
  private static initialized: boolean = false;

  static init(context: common.Context): void {
    AppContext.abilityContext = context;
    AppContext.initialized = true;
    Log.configureFileLogging(context.filesDir);
    Log.info('AppContext', 'filesDir=' + AppContext.filesDir);
  }

  /**
   * Fallback registration for entry points that do not go through
   * EntryAbility.onCreate - most importantly the DevEco Previewer, which never
   * runs the ability lifecycle. UI pages pass the host context they get from
   * `getUIContext().getHostContext()`; when that is undefined (the Previewer
   * can return undefined) we fall back to the global getContext() API.
   */
  static ensureInitialized(context: common.Context | undefined): void {
    if (AppContext.initialized) {
      return;
    }
    if (context !== undefined) {
      AppContext.init(context);
      Log.info('AppContext', 'initialized from UI host context');
      return;
    }
    try {
      const fallback = getContext() as common.Context;
      if (fallback !== undefined && fallback !== null) {
        AppContext.init(fallback);
        Log.info('AppContext', 'initialized from global getContext()');
      } else {
        Log.warn('AppContext', 'no context available yet');
      }
    } catch (error) {
      Log.warn('AppContext', `getContext() fallback failed: ${error}`);
    }
  }

  static get isInitialized(): boolean {
    return AppContext.initialized;
  }

  static get context(): common.Context {
    const ctx = AppContext.abilityContext;
    if (ctx === undefined) {
      throw new Error('AppContext is not initialized');
    }
    return ctx;
  }

  /** App sandbox files directory - persistent across upgrades. */
  static get filesDir(): string {
    return AppContext.context.filesDir;
  }

  /** App sandbox cache directory - may be reclaimed by the system. */
  static get cacheDir(): string {
    return AppContext.context.cacheDir;
  }

  static get tempDir(): string {
    return AppContext.context.tempDir;
  }

  /** Where installed comic source scripts live. */
  static get sourceDir(): string {
    return AppContext.filesDir + '/sources';
  }

  /** Where downloaded page images are cached. */
  static get imageCacheDir(): string {
    return AppContext.cacheDir + '/images';
  }

  /** Local comics imported into the app sandbox. */
  static get localComicDir(): string {
    return AppContext.filesDir + '/local_comics';
  }

  static get bundleName(): string {
    return AppContext.context.applicationInfo.name;
  }
}
