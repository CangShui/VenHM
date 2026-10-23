import { relationalStore } from '@kit.ArkData';
import { AppContext } from '../foundation/AppContext';
import { Log } from '../foundation/Log';

/**
 * SQLite access layer.
 *
 * Dart original: VeneraNext used `package:sqlite3` with *synchronous* calls
 * across 11 files. The port mostly uses async reads; API 12+ executeSync is
 * used for small progress/cookie writes where ordering and durability matter.
 *
 * Schema differences from Dart are deliberate:
 *  - favorites use one table with a `folder` column instead of one table per
 *    folder (Dart created tables dynamically per folder).
 *  - `ComicType` integers come from ComicType.hashKey (FNV-1a), not Dart's
 *    String.hashCode, so this database is not binary-compatible with the
 *    Flutter app's database. Original backup/data import needs explicit schema
 *    and ID conversion as part of full migration, not opening that DB directly.
 */
export class Database {
  private static store: relationalStore.RdbStore | undefined = undefined;
  private static initializing: Promise<void> | undefined = undefined;

  static async init(): Promise<void> {
    if (Database.store !== undefined) {
      return;
    }
    if (Database.initializing !== undefined) {
      return Database.initializing;
    }
    Database.initializing = Database.open();
    try {
      await Database.initializing;
    } finally {
      Database.initializing = undefined;
    }
  }

  private static async open(): Promise<void> {
    const config: relationalStore.StoreConfig = {
      name: 'venera_hm.db',
      securityLevel: relationalStore.SecurityLevel.S1
    };
    const store = await relationalStore.getRdbStore(AppContext.context, config);
    await Database.createTables(store);
    // Publish only after all migrations succeed; retries must not skip them.
    Database.store = store;
    Log.info('Database', 'rdb store ready');
  }

  static get rdb(): relationalStore.RdbStore {
    const store = Database.store;
    if (store === undefined) {
      throw new Error('Database.init() has not been called');
    }
    return store;
  }

  private static async createTables(store: relationalStore.RdbStore): Promise<void> {
    // Favorites: Dart keyed tables per folder; the port keeps one table + folder.
    await store.executeSql(
      'CREATE TABLE IF NOT EXISTS favorites (' +
        'id TEXT NOT NULL, ' +
        'type INTEGER NOT NULL, ' +
        'source_key TEXT NOT NULL DEFAULT \'\', ' +
        'name TEXT NOT NULL, ' +
        'author TEXT NOT NULL DEFAULT \'\', ' +
        'tags TEXT NOT NULL DEFAULT \'\', ' +
        'cover_path TEXT NOT NULL DEFAULT \'\', ' +
        'folder TEXT NOT NULL DEFAULT \'\', ' +
        'time TEXT NOT NULL, ' +
        'display_order INTEGER NOT NULL DEFAULT 0, ' +
        'PRIMARY KEY (id, type, folder))');

    // Folder list. Dart created one table per folder, so empty folders survived
    // in sqlite_master; a `folder` column cannot represent them, hence this
    // explicit table (Dart's `folder_order` plus the folder-name set).
    await store.executeSql(
      'CREATE TABLE IF NOT EXISTS favorite_folders (' +
        'name TEXT PRIMARY KEY, ' +
        'display_order INTEGER NOT NULL DEFAULT 0)');

    // Reading history, mirroring the Dart `history` table columns.
    await store.executeSql(
      'CREATE TABLE IF NOT EXISTS history (' +
        'id TEXT NOT NULL, ' +
        'type INTEGER NOT NULL, ' +
        'title TEXT NOT NULL DEFAULT \'\', ' +
        'subtitle TEXT NOT NULL DEFAULT \'\', ' +
        'cover TEXT NOT NULL DEFAULT \'\', ' +
        'time INTEGER NOT NULL, ' +
        'ep INTEGER NOT NULL DEFAULT 1, ' +
        'page INTEGER NOT NULL DEFAULT 1, ' +
        'read_episode TEXT NOT NULL DEFAULT \'\', ' +
        'max_page INTEGER, ' +
        'chapter_group INTEGER, ' +
        'read_duration_ms INTEGER NOT NULL DEFAULT 0, ' +
        'PRIMARY KEY (id, type))');

    // Upgrade existing installs in place. Do not rebuild/drop user history.
    const columns = await store.querySql('PRAGMA table_info(history)');
    const names: string[] = [];
    try {
      while (columns.goToNextRow()) {
        names.push(columns.getString(columns.getColumnIndex('name')));
      }
    } finally {
      columns.close();
    }
    if (names.indexOf('source_key') < 0) {
      await store.executeSql("ALTER TABLE history ADD COLUMN source_key TEXT NOT NULL DEFAULT ''");
    }
    if (names.indexOf('ep_id') < 0) {
      // NULL = legacy index-only record; '' = legitimate implicit chapter ID.
      await store.executeSql('ALTER TABLE history ADD COLUMN ep_id TEXT');
    }

    // Installed comic sources (metadata only; scripts live in filesDir/sources).
    await store.executeSql(
      'CREATE TABLE IF NOT EXISTS sources (' +
        'key TEXT PRIMARY KEY, ' +
        'name TEXT NOT NULL, ' +
        'version TEXT NOT NULL, ' +
        'url TEXT NOT NULL DEFAULT \'\', ' +
        'file_name TEXT NOT NULL DEFAULT \'\', ' +
        'installed_at INTEGER NOT NULL)');

    // Per-source persistent data (Dart stored `comic_source/<key>.data` JSON).
    await store.executeSql(
      'CREATE TABLE IF NOT EXISTS source_data (' +
        'source_key TEXT NOT NULL, ' +
        'data_key TEXT NOT NULL, ' +
        'data_value TEXT NOT NULL, ' +
        'PRIMARY KEY (source_key, data_key))');

    await Database.ensureCookieSchema(store);

    await store.executeSql(
      'CREATE INDEX IF NOT EXISTS idx_history_time ON history (time DESC)');

    // Seed folders without touching existing favourites. '' is the port's
    // implicit default folder; Dart instead forced a named tracking folder.
    await store.executeSql(
      "INSERT OR IGNORE INTO favorite_folders (name, display_order) VALUES ('', 0)");
    await store.executeSql(
      'INSERT OR IGNORE INTO favorite_folders (name, display_order) ' +
        'SELECT DISTINCT folder, 1 FROM favorites');

    Log.info('Database', 'tables ensured');
  }

  static async execute(sql: string, args?: relationalStore.ValueType[]): Promise<void> {
    await Database.rdb.executeSql(sql, args);
  }

  static async ensureCookieSchema(store: relationalStore.RdbStore): Promise<void> {
    await store.executeSql(
      'CREATE TABLE IF NOT EXISTS cookies (' +
        'name TEXT NOT NULL, value TEXT NOT NULL, domain TEXT NOT NULL, ' +
        'path TEXT NOT NULL, host_only INTEGER NOT NULL, secure INTEGER NOT NULL, ' +
        'http_only INTEGER NOT NULL, expires_at_ms INTEGER NOT NULL DEFAULT 0, same_site TEXT NOT NULL DEFAULT \'\', ' +
        'PRIMARY KEY (name, domain, path))');
    const cookieColumns = await store.querySql('PRAGMA table_info(cookies)');
    let hasSameSite = false;
    try {
      while (cookieColumns.goToNextRow()) {
        if (cookieColumns.getString(cookieColumns.getColumnIndex('name')) === 'same_site') { hasSameSite = true; }
      }
    } finally { cookieColumns.close(); }
    if (!hasSameSite) {
      await store.executeSql("ALTER TABLE cookies ADD COLUMN same_site TEXT NOT NULL DEFAULT ''");
      Log.audit('cookie-schema-migration', 'Cookie结构迁移', '保留原会话值与作用域，新增SameSite字段；不清空任何Cookie');
    }
  }

  static async query(sql: string, args?: relationalStore.ValueType[]): Promise<relationalStore.ResultSet> {
    return await Database.rdb.querySql(sql, args);
  }
}
