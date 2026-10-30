import { fileIo as fs } from '@kit.CoreFileKit';
import { ComicSource } from './ComicSource';
import { LocalSource } from './LocalSource';
import { ComicSourceParser, JsComicSource } from './JsComicSource';
import { SourceInstaller } from './SourceInstaller';
import { SourceDataStore } from './SourceDataStore';
import { JsEngine } from './JsEngine';
import { InstalledSource, SourceDao } from '../storage/SourceDao';
import { Log } from '../foundation/Log';
import { firstWhereOrNull } from '../foundation/Extensions';

/**
 * Comic source registry.
 *
 * Dart original: lib/features/comic_source/comic_source_manager.dart.
 * It scanned `<dataPath>/comic_source/*.js`, parsed each script through QuickJS
 * and registered the result. The port does the same from the `sources` table,
 * and keeps built-in ArkTS sources registered so the app is usable even when the
 * JS runtime or a script fails.
 */
export class SourceManager {
  private static readonly sources: ComicSource[] = [];
  private static initialized: boolean = false;
  private static loadErrors: string[] = [];

  static async init(): Promise<void> {
    if (SourceManager.initialized) {
      return;
    }
    SourceManager.sources.length = 0;
    SourceManager.loadErrors = [];
    SourceManager.register(new LocalSource());
    await SourceManager.loadInstalledScripts();
    SourceManager.initialized = true;
    Log.info('SourceManager',
      `registered ${SourceManager.sources.length} source(s), ${SourceManager.loadErrors.length} failure(s)`);
  }

  /** Parse every installed `.js` source and register it. */
  private static async loadInstalledScripts(): Promise<void> {
    if (!JsEngine.isAvailable) {
      Log.warn('SourceManager', 'QuickJS unavailable - installed scripts are not loaded');
      return;
    }
    let installed: InstalledSource[] = [];
    try {
      installed = await SourceDao.list();
    } catch (error) {
      Log.warn('SourceManager', `cannot list installed sources: ${error}`);
      return;
    }
    for (let i = 0; i < installed.length; i++) {
      const item = installed[i];
      try {
        const path = SourceInstaller.scriptPath(item.key);
        if (!fs.accessSync(path)) {
          SourceManager.loadErrors.push(`${item.name}: 脚本文件缺失`);
          continue;
        }
        await SourceDataStore.preload(item.key);
        const script = fs.readTextSync(path);
        const source: JsComicSource = await ComicSourceParser.parse(script, path);
        SourceManager.register(source);
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        SourceManager.loadErrors.push(`${item.name}: ${message}`);
        Log.error('SourceManager', `loading ${item.key} failed: ${message}`);
      }
    }
  }

  /** Failures from the last init(), surfaced in the source manager page. */
  static get errors(): string[] {
    return SourceManager.loadErrors;
  }

  /** Register, replacing an older instance of the same key with the new one. */
  static register(source: ComicSource): void {
    const index = SourceManager.sources.findIndex((item: ComicSource) => item.key === source.key);
    if (index >= 0) {
      SourceManager.sources.splice(index, 1);
    }
    SourceManager.sources.push(source);
  }

  /**
   * Re-parse every installed script (built-in sources stay). Called after the
   * script set changes so capability changes such as a new account declaration
   * are visible immediately instead of after a full app restart.
   */
  static async reloadInstalled(): Promise<void> {
    SourceManager.sources.splice(0, SourceManager.sources.length,
      ...SourceManager.sources.filter((item: ComicSource) => item.key === 'local'));
    SourceManager.loadErrors = [];
    await SourceManager.loadInstalledScripts();
    Log.info('SourceManager', `reloaded installed scripts; ${SourceManager.sources.length} source(s)`);
  }

  static unregister(key: string): void {
    const index = SourceManager.sources.findIndex((item: ComicSource) => item.key === key);
    if (index >= 0) {
      SourceManager.sources.splice(index, 1);
    }
  }

  static all(): ComicSource[] {
    return SourceManager.sources;
  }

  static find(key: string): ComicSource | undefined {
    return firstWhereOrNull(SourceManager.sources, (item: ComicSource) => item.key === key);
  }

  static get isEmpty(): boolean {
    return SourceManager.sources.length === 0;
  }

  /** Sources that can be picked in the search page. */
  static searchable(): ComicSource[] {
    return SourceManager.sources.filter((item: ComicSource) => item.supportsSearch);
  }
}
