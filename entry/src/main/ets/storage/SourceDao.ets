import { Database } from './Database';
import { Log } from '../foundation/Log';

/** An installed comic source script (metadata; the .js lives in filesDir/sources). */
export class InstalledSource {
  key: string = '';
  name: string = '';
  version: string = '';
  url: string = '';
  fileName: string = '';
  installedAt: number = 0;
}

/**
 * Persistence for installed sources.
 * Dart original: lib/features/comic_source/comic_source_manager.dart kept this
 * implicitly (one file per source under `<dataPath>/comic_source`); the port also
 * keeps a table so the UI can list sources without scanning the disk.
 */
export class SourceDao {
  static async upsert(source: InstalledSource): Promise<void> {
    await Database.execute(
      'INSERT OR REPLACE INTO sources (key, name, version, url, file_name, installed_at) ' +
        'VALUES (?, ?, ?, ?, ?, ?)',
      [source.key, source.name, source.version, source.url, source.fileName, source.installedAt]);
    Log.info('SourceDao', `saved ${source.key}@${source.version}`);
  }

  static async list(): Promise<InstalledSource[]> {
    const result = await Database.query(
      'SELECT key, name, version, url, file_name, installed_at FROM sources ORDER BY name');
    const out: InstalledSource[] = [];
    try {
      while (result.goToNextRow()) {
        const item = new InstalledSource();
        item.key = result.getString(result.getColumnIndex('key'));
        item.name = result.getString(result.getColumnIndex('name'));
        item.version = result.getString(result.getColumnIndex('version'));
        item.url = result.getString(result.getColumnIndex('url'));
        item.fileName = result.getString(result.getColumnIndex('file_name'));
        item.installedAt = result.getLong(result.getColumnIndex('installed_at'));
        out.push(item);
      }
    } finally {
      result.close();
    }
    return out;
  }

  static async find(key: string): Promise<InstalledSource | undefined> {
    const result = await Database.query(
      'SELECT key, name, version, url, file_name, installed_at FROM sources WHERE key = ?', [key]);
    try {
      if (result.goToFirstRow()) {
        const item = new InstalledSource();
        item.key = result.getString(result.getColumnIndex('key'));
        item.name = result.getString(result.getColumnIndex('name'));
        item.version = result.getString(result.getColumnIndex('version'));
        item.url = result.getString(result.getColumnIndex('url'));
        item.fileName = result.getString(result.getColumnIndex('file_name'));
        item.installedAt = result.getLong(result.getColumnIndex('installed_at'));
        return item;
      }
      return undefined;
    } finally {
      result.close();
    }
  }

  static async remove(key: string): Promise<void> {
    await Database.execute('DELETE FROM sources WHERE key = ?', [key]);
  }

  static async count(): Promise<number> {
    const result = await Database.query('SELECT COUNT(*) AS c FROM sources');
    try {
      if (result.goToFirstRow()) {
        return result.getLong(result.getColumnIndex('c'));
      }
      return 0;
    } finally {
      result.close();
    }
  }
}
