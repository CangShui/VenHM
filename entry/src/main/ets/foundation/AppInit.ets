import { Settings } from './Settings';
import { Database } from '../storage/Database';
import { CookieJar } from '../network/CookieJar';
import { SourceManager } from '../source/SourceManager';
import { SourceSelfTest } from '../source/SourceSelfTest';
import { JsEngine } from '../source/JsEngine';
import { Log } from './Log';
import { SourceSettingsUsability } from '../features/SourceSettingsUsability';
import { ImageTransformUsability } from '../features/ImageTransformUsability';
import { SourceAccountUsability } from '../features/SourceAccountUsability';
import { NativeHttpCodecUsability } from '../features/NativeHttpCodecUsability';

/**
 * Startup orchestration.
 *
 * Dart original: lib/app_runtime/init.dart. The Flutter sequence waited on
 * cookie jar, rhttp, history/favorites managers, translations, QuickJS and the
 * comic source manager. The port keeps the same ordering idea but only the
 * pieces that exist today; later modules append their initializers here.
 */
export class AppInit {
  private static done: boolean = false;
  private static initializing: Promise<void> | undefined = undefined;

  static async init(): Promise<void> {
    if (AppInit.done) {
      return;
    }
    if (AppInit.initializing !== undefined) {
      return AppInit.initializing;
    }
    AppInit.initializing = AppInit.run();
    try {
      await AppInit.initializing;
    } finally {
      // A transient DB/source error must not permanently poison retry buttons.
      AppInit.initializing = undefined;
    }
  }

  private static async run(): Promise<void> {
    const start = Date.now();
    await Settings.init();
    await Database.init();
    await CookieJar.init();
    try {
      await CookieJar.selfTest();
      Log.info('AppInit', 'cookie contracts OK: scope/path/secure/expiry/persistence');
    } catch (error) {
      Log.error('AppInit', `cookie contract FAILED: ${error}`);
    }
    // Load the native QuickJS module + assets/init.js before sources: installed
    // .js sources are only usable once the engine is up.
    await JsEngine.init();
    try { NativeHttpCodecUsability.run(); }
    catch (error) { Log.audit('native-http-codec-init', '原生解码契约失败', '固定向量或上限校验失败；不能声明原生解码可用'); }
    if (JsEngine.isAvailable) {
      try { await ImageTransformUsability.run(); }
      catch (error) { Log.error('AppInit', `image pixel contract FAILED: ${String(error)}`); }
    }
    // Index installs a component-owned dialog builder before invoking init.
    await SourceManager.init();
    try {
      await SourceSettingsUsability.restoreIfEnabled();
    } catch (error) {
      Log.warn('AppInit', `isolated source-settings fixture not restored: ${error}`);
    }
    try { await SourceAccountUsability.restoreIfEnabled(); }
    catch (error) { Log.audit('auth-fixture-restore', '合成账号恢复异常', '只影响合成测试注册；没有自动登录实际源'); }
    AppInit.done = true;
    Log.info('AppInit', `ready in ${Date.now() - start}ms`);
    // Fire-and-forget: the verdicts land in hilog so the source compatibility
    // matrix can be read off the device after every install.
    SourceSelfTest.run().catch((error: Object) => {
      Log.warn('AppInit', `self test failed: ${error}`);
    });
  }

  static get isReady(): boolean {
    return AppInit.done;
  }
}
