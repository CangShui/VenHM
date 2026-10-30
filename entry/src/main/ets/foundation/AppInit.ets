import { fileIo as fs } from '@kit.CoreFileKit';
import { AppContext } from './AppContext';
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
    // The retired backup screen persisted only its endpoint; credentials were
    // session-only. Remove that one known key, preserving all reader settings.
    await Settings.remove('webdavEndpoint');
    AppInit.removeRetiredPictureCopies();
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

  /** Upgrade-only cleanup of the old module's exact private folder/UUID format.
   * No recursive deletion: unknown entries, directories and links are not owned.
   * The old implementation had no marker file; do not infer ownership by prefix.
   */
  static removeRetiredPictureCopies(): void {
    const root = AppContext.filesDir;
    if (!root.startsWith('/') || root.endsWith('/') || root.includes('\\') || root.includes('//') ||
      root.split('/').some((part: string) => part === '..' || part === '.')) {
      Log.warn('AppInit', 'retired image cleanup skipped: invalid sandbox root');
      return;
    }
    if (!fs.accessSync(root)) { return; }
    if (fs.lstatSync(root).isSymbolicLink() || !fs.statSync(root).isDirectory()) {
      Log.warn('AppInit', 'retired image cleanup skipped: unsafe sandbox root');
      return;
    }
    const directory = `${root}/picture_favorites`;
    if (!fs.accessSync(directory)) { return; }
    if (fs.lstatSync(directory).isSymbolicLink() || !fs.statSync(directory).isDirectory()) {
      Log.warn('AppInit', 'retired image cleanup skipped: unsafe legacy directory');
      return;
    }
    for (const name of fs.listFileSync(directory)) {
      // Exact old UUID-derived file format. No separators, nesting or arbitrary suffixes.
      if (!/^[a-f0-9]{32}\.image$/.test(name)) { continue; }
      const file = `${directory}/${name}`;
      if (fs.lstatSync(file).isSymbolicLink() || !fs.statSync(file).isFile()) { continue; }
      // Absolute path was verified under the trusted context root and exact owned directory.
      fs.unlinkSync(file);
    }
    // Never rmdir: that SDK operation can recurse; leave an empty harmless folder.
    // I/O errors propagate for startup retry instead of silently stranding known copies.
  }

  static get isReady(): boolean {
    return AppInit.done;
  }
}
