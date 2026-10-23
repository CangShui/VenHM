import { fileIo as fs } from '@kit.CoreFileKit';
import { SourceCatalogEntry } from './SourceRepository';
import { InstalledSource, SourceDao } from '../storage/SourceDao';
import { HttpClient, HttpResponse } from '../network/HttpClient';
import { AppContext } from '../foundation/AppContext';
import { JsRuntimeStatus } from './JsRuntime';
import { Log } from '../foundation/Log';

/** Same entry-class rule VeneraNext's parser enforces before instantiation. */
const CLASS_PATTERN = new RegExp(
  '^\\s*class\\s+([a-zA-Z_$][a-zA-Z0-9_$]*)\\s+extends\\s+ComicSource\\b', 'm');
const KEY_PATTERN = new RegExp('^[a-zA-Z_][a-zA-Z0-9_]*$');

export class SourceInstallResult {
  key: string = '';
  name: string = '';
  version: string = '';
  scriptPath: string = '';
  /** False when the script is on disk but the JS runtime cannot run it yet. */
  runtimeReady: boolean = false;
  message: string = '';
}

/**
 * Downloads a source script and stores it in the app sandbox.
 *
 * Dart original: lib/features/comic_source/source_installation.dart +
 * ComicSourceParser.createAndParse (which wrote the file and then parsed it).
 * The port keeps the download/validate/write half; the parse half needs the
 * QuickJS runtime and is reported through `runtimeReady`.
 */
export class SourceInstaller {
  static ensureSourceDir(): void {
    const dir = AppContext.sourceDir;
    if (!fs.accessSync(dir)) {
      fs.mkdirSync(dir, true);
      Log.info('SourceInstaller', `created ${dir}`);
    }
  }

  static scriptPath(key: string): string {
    return `${AppContext.sourceDir}/${key}.js`;
  }

  /**
   * Download + validate + persist one catalog entry.
   * Throws with a user-readable message on any failure.
   */
  static async install(entry: SourceCatalogEntry): Promise<SourceInstallResult> {
    if (!KEY_PATTERN.test(entry.key)) {
      throw new Error(`源 key 不合法: ${entry.key}`);
    }
    SourceInstaller.ensureSourceDir();

    const response: HttpResponse = await HttpClient.getText(entry.url);
    if (!response.ok) {
      throw new Error(`下载脚本失败: HTTP ${response.status}`);
    }
    const script = response.body;
    if (script.length === 0) {
      throw new Error('下载到的脚本为空');
    }

    const match = CLASS_PATTERN.exec(script.replace('\uFEFF', ''));
    if (match === null) {
      throw new Error('脚本不是有效的漫画源（缺少 extends ComicSource 的入口类）');
    }

    // Static cross-check of the declared key. The authoritative check happens
    // in the JS parser (expectedKey), but failing early gives a better message.
    const declaredKey = SourceInstaller.readDeclaredKey(script);
    if (declaredKey !== undefined && declaredKey !== entry.key) {
      throw new Error(`脚本声明的 key(${declaredKey}) 与仓库条目(${entry.key}) 不一致`);
    }

    const path = SourceInstaller.scriptPath(entry.key);
    const file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, script);
    } finally {
      fs.closeSync(file);
    }

    const installed = new InstalledSource();
    installed.key = entry.key;
    installed.name = entry.name;
    installed.version = entry.version;
    installed.url = entry.url;
    installed.fileName = `${entry.key}.js`;
    installed.installedAt = Date.now();
    await SourceDao.upsert(installed);

    const result = new SourceInstallResult();
    result.key = entry.key;
    result.name = entry.name;
    result.version = entry.version;
    result.scriptPath = path;
    result.runtimeReady = JsRuntimeStatus.isAvailable;
    result.message = JsRuntimeStatus.isAvailable
      ? `已安装并加载 ${entry.name}`
      : `脚本已下载到 ${path}，但 QuickJS 运行时未接入，暂不能加载`;
    Log.info('SourceInstaller', result.message);
    return result;
  }

  /** Best-effort static read of `key = "..."` from a source script. */
  static readDeclaredKey(script: string): string | undefined {
    const match = new RegExp('^\\s*(?:static\\s+)?key\\s*=\\s*["\']([^"\']*)["\']', 'm').exec(script);
    return match === null ? undefined : match[1];
  }

  static async listInstalled(): Promise<InstalledSource[]> {
    return await SourceDao.list();
  }

  static async uninstall(key: string): Promise<void> {
    const path = SourceInstaller.scriptPath(key);
    if (fs.accessSync(path)) {
      fs.unlinkSync(path);
    }
    await SourceDao.remove(key);
    Log.info('SourceInstaller', `uninstalled ${key}`);
  }

  static isInstalled(key: string): boolean {
    return fs.accessSync(SourceInstaller.scriptPath(key));
  }
}
