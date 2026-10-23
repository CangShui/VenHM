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

  static register(source: ComicSource): void {
    const existing = SourceManager.find(source.key);
    if (existing !== undefined) {
      Log.warn('SourceManager', `source ${source.key} already registered`);
      return;
    }
    SourceManager.sources.push(source);
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
