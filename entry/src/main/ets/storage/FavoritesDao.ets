import { relationalStore } from '@kit.ArkData';
import { Comic } from '../model/Comic';
import { ComicType } from '../model/ComicType';
import { Database } from './Database';
import { Log } from '../foundation/Log';

/**
 * A locally stored favorite.
 *
 * Dart original: lib/features/favorites/favorites_manager.dart `FavoriteItem`
 * (which `implements Comic`). ArkTS has no structural typing, so the Comic
 * members are declared explicitly here; `name`/`author`/`coverPath` are kept
 * because the Dart UI and the database columns use those names.
 */
export class FavoriteItem implements Comic {
  // Comic members
  title: string = '';
  subtitle: string = '';
  cover: string = '';
  description: string = '';
  sourceKey: string = '';
  maxPage?: number;
  language?: string;
  favoriteId?: string;
  stars?: number;

  // favorite-specific members (mirroring the Dart columns)
  id: string = '';
  name: string = '';
  author: string = '';
  tags: string[] = [];
  coverPath: string = '';
  type: ComicType = ComicType.local;
  folder: string = '';
  time: string = '';

  static now(): string {
    const d = new Date();
    const pad = (n: number): string => (n < 10 ? `0${n}` : `${n}`);
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ` +
      `${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
  }

  /** Build a favorite from a comic shown in the UI. */
  static fromComic(comic: Comic, folder: string): FavoriteItem {
    const item = new FavoriteItem();
    item.id = comic.id;
    item.name = comic.title;
    item.author = comic.subtitle;
    item.tags = comic.tags;
    item.coverPath = comic.cover;
    item.sourceKey = comic.sourceKey;
    item.type = ComicType.fromKey(comic.sourceKey);
    item.folder = folder;
    item.time = FavoriteItem.now();
    item.syncComicFields();
    return item;
  }

  /**
   * Keep the Comic-facing fields in sync with the stored fields.
   * `sourceKey` is authoritative (it is what reopens the comic) - only the
   * display fields are derived here.
   */
  syncComicFields(): void {
    this.title = this.name;
    this.subtitle = this.author;
    this.cover = this.coverPath;
    this.description = this.time;
  }
}

/** A folder plus its comic count, matching Dart's `folderNames` + `counts`. */
export class FavoriteFolder {
  name: string = '';
  count: number = 0;

  /** '' is the port's implicit default folder (see Database.ets). */
  get displayName(): string {
    return this.name.length === 0 ? '默认收藏夹' : this.name;
  }
}

/**
 * Favorites persistence.
 *
 * Schema note: Dart created one table per folder; the port keeps a single
 * `favorites` table keyed by (id, type, folder) plus a `favorite_folders`
 * table, so a comic can live in several folders and empty folders survive.
 */
export class FavoritesDao {
  private static listeners: Array<() => void> = [];

  static addListener(listener: () => void): void {
    if (FavoritesDao.listeners.indexOf(listener) < 0) {
      FavoritesDao.listeners.push(listener);
    }
  }

  static removeListener(listener: () => void): void {
    FavoritesDao.listeners = FavoritesDao.listeners.filter((item: () => void) => item !== listener);
  }

  private static changed(): void {
    for (const listener of FavoritesDao.listeners) {
      try {
        listener();
      } catch (error) {
        Log.warn('FavoritesDao', `listener failed: ${error}`);
      }
    }
  }

  /** Mirrors Dart `validateFolderName`: returns an error message or null. */
  static validateFolderName(name: string, existing: string[]): string | null {
    if (name.length === 0) {
      return '收藏夹名不能为空';
    }
    if (name.length > 50) {
      return '收藏夹名过长（最多 50 字）';
    }
    if (name.indexOf('"') >= 0) {
      return '收藏夹名不能包含双引号';
    }
    if (existing.indexOf(name) >= 0) {
      return '同名收藏夹已存在';
    }
    return null;
  }

  static async listFolders(): Promise<FavoriteFolder[]> {
    const result = await Database.query(
      'SELECT f.name AS name, ' +
        '(SELECT COUNT(*) FROM favorites v WHERE v.folder = f.name) AS c ' +
        'FROM favorite_folders f ORDER BY f.display_order, f.name');
    const folders: FavoriteFolder[] = [];
    try {
      while (result.goToNextRow()) {
        const folder = new FavoriteFolder();
        folder.name = result.getString(result.getColumnIndex('name'));
        folder.count = result.getLong(result.getColumnIndex('c'));
        folders.push(folder);
      }
    } finally {
      result.close();
    }
    return folders;
  }

  /** Folder names in display order ('' first, then by folder order). */
  static async folderNames(): Promise<string[]> {
    const folders = await FavoritesDao.listFolders();
    return folders.map((item: FavoriteFolder) => item.name);
  }

  /**
   * Create a folder. Dart threw on empty/duplicate names; the UI validates
   * first and this keeps the same rejection instead of silently renaming.
   */
  static async createFolder(name: string): Promise<void> {
    const existing = await FavoritesDao.folderNames();
    const error = FavoritesDao.validateFolderName(name, existing);
    if (error !== null) {
      throw new Error(error);
    }
    Database.rdb.executeSync(
      'INSERT INTO favorite_folders (name, display_order) VALUES (?, ' +
        '((SELECT IFNULL(MAX(display_order), 0) FROM favorite_folders) + 1))', [name]);
    FavoritesDao.changed();
    Log.info('FavoritesDao', `created folder ${name}`);
  }

  /** Dart `rename`: rejects duplicates, then moves every favourite across. */
  static async renameFolder(before: string, after: string): Promise<void> {
    if (before === after) {
      return;
    }
    if (before.length === 0) {
      throw new Error('默认收藏夹不能重命名');
    }
    const existing = await FavoritesDao.folderNames();
    const error = FavoritesDao.validateFolderName(after, existing);
    if (error !== null) {
      throw new Error(error);
    }
    Database.rdb.beginTransaction();
    try {
      Database.rdb.executeSync('UPDATE favorites SET folder = ? WHERE folder = ?', [after, before]);
      Database.rdb.executeSync('UPDATE favorite_folders SET name = ? WHERE name = ?', [after, before]);
      Database.rdb.commit();
    } catch (error) {
      Database.rdb.rollBack();
      throw new Error(error instanceof Error ? error.message : String(error));
    }
    FavoritesDao.changed();
  }

  /** Dart `deleteFolder` dropped the table, i.e. the folder and its comics. */
  static async deleteFolder(name: string): Promise<void> {
    if (name.length === 0) {
      throw new Error('默认收藏夹不能删除');
    }
    Database.rdb.beginTransaction();
    try {
      Database.rdb.executeSync('DELETE FROM favorites WHERE folder = ?', [name]);
      Database.rdb.executeSync('DELETE FROM favorite_folders WHERE name = ?', [name]);
      Database.rdb.commit();
    } catch (error) {
      Database.rdb.rollBack();
      throw new Error(error instanceof Error ? error.message : String(error));
    }
    FavoritesDao.changed();
  }

  /** Dart `updateOrder` over its `folder_order` table. */
  static async updateFolderOrder(names: string[]): Promise<void> {
    Database.rdb.beginTransaction();
    try {
      for (let i = 0; i < names.length; i++) {
        Database.rdb.executeSync(
          'UPDATE favorite_folders SET display_order = ? WHERE name = ?', [i, names[i]]);
      }
      Database.rdb.commit();
    } catch (error) {
      Database.rdb.rollBack();
      throw new Error(error instanceof Error ? error.message : String(error));
    }
    FavoritesDao.changed();
  }

  /** Dart `addComic` returned false when the comic was already in the folder. */
  static async add(item: FavoriteItem): Promise<boolean> {
    if (await FavoritesDao.isFavoriteIn(item.folder, item.id, item.type.value)) {
      return false;
    }
    // `newFavoriteAddTo` defaults to "end" upstream: maxValue + 1.
    Database.rdb.executeSync(
      'INSERT OR REPLACE INTO favorites ' +
        '(id, type, source_key, name, author, tags, cover_path, folder, time, display_order) ' +
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ' +
        '(SELECT IFNULL(MAX(display_order), 0) + 1 FROM favorites WHERE folder = ?))',
      [item.id, item.type.value, item.sourceKey, item.name, item.author, item.tags.join(','),
        item.coverPath, item.folder, item.time, item.folder]);
    FavoritesDao.changed();
    Log.info('FavoritesDao', `added ${item.id} to ${item.folder}`);
    return true;
  }

  static async remove(id: string, type: number, folder: string): Promise<void> {
    Database.rdb.executeSync(
      'DELETE FROM favorites WHERE id = ? AND type = ? AND folder = ?', [id, type, folder]);
    FavoritesDao.changed();
  }

  /** Remove from every folder, as Dart's detail page did when fully unfavourited. */
  static async removeEverywhere(id: string, type: number): Promise<void> {
    Database.rdb.executeSync('DELETE FROM favorites WHERE id = ? AND type = ?', [id, type]);
    FavoritesDao.changed();
  }

  static async isFavoriteIn(folder: string, id: string, type: number): Promise<boolean> {
    const result = await Database.query(
      'SELECT COUNT(*) AS c FROM favorites WHERE id = ? AND type = ? AND folder = ?',
      [id, type, folder]);
    try {
      return result.goToFirstRow() && result.getLong(result.getColumnIndex('c')) > 0;
    } finally {
      result.close();
    }
  }

  /** True when the comic is in at least one folder. */
  static async isFavorite(id: string, type: number): Promise<boolean> {
    const result = await Database.query(
      'SELECT COUNT(*) AS c FROM favorites WHERE id = ? AND type = ?', [id, type]);
    try {
      if (result.goToFirstRow()) {
        return result.getLong(result.getColumnIndex('c')) > 0;
      }
      return false;
    } finally {
      result.close();
    }
  }

  /** Folders containing this comic, for the details page Add/Remove panel. */
  static async foldersOf(id: string, type: number): Promise<string[]> {
    const result = await Database.query(
      'SELECT folder FROM favorites WHERE id = ? AND type = ? ORDER BY folder', [id, type]);
    const folders: string[] = [];
    try {
      while (result.goToNextRow()) {
        folders.push(result.getString(result.getColumnIndex('folder')));
      }
    } finally {
      result.close();
    }
    return folders;
  }

  static async list(folder?: string): Promise<FavoriteItem[]> {
    const columns =
      'id, type, source_key, name, author, tags, cover_path, folder, time';
    const sql = folder === undefined
      ? `SELECT ${columns} FROM favorites ORDER BY folder, display_order, time`
      : `SELECT ${columns} FROM favorites WHERE folder = ? ORDER BY display_order, time`;
    const args: relationalStore.ValueType[] | undefined =
      folder === undefined ? undefined : [folder];
    const result = await Database.query(sql, args);
    const items: FavoriteItem[] = [];
    try {
      while (result.goToNextRow()) {
        items.push(FavoritesDao.fromRow(result));
      }
    } finally {
      result.close();
    }
    return items;
  }

  private static fromRow(result: relationalStore.ResultSet): FavoriteItem {
    const item = new FavoriteItem();
    item.id = result.getString(result.getColumnIndex('id'));
    item.type = ComicType.fromValue(result.getLong(result.getColumnIndex('type')));
    item.sourceKey = result.getString(result.getColumnIndex('source_key'));
    item.name = result.getString(result.getColumnIndex('name'));
    item.author = result.getString(result.getColumnIndex('author'));
    const tagText = result.getString(result.getColumnIndex('tags'));
    item.tags = tagText.length === 0 ? [] : tagText.split(',').filter((t: string) => t.length > 0);
    item.coverPath = result.getString(result.getColumnIndex('cover_path'));
    item.folder = result.getString(result.getColumnIndex('folder'));
    item.time = result.getString(result.getColumnIndex('time'));
    item.syncComicFields();
    return item;
  }

  /**
   * Dart `moveFavorite`: no-op if the target already has the comic, otherwise
   * insert into the target (at the top, minValue - 1) and delete the source.
   */
  static async moveFavorite(source: string, target: string, id: string, type: number): Promise<boolean> {
    if (source === target) {
      return false;
    }
    if (await FavoritesDao.isFavoriteIn(target, id, type)) {
      return false;
    }
    Database.rdb.beginTransaction();
    try {
      Database.rdb.executeSync(
        'INSERT INTO favorites (id, type, source_key, name, author, tags, cover_path, folder, time, display_order) ' +
          'SELECT id, type, source_key, name, author, tags, cover_path, ?, time, ' +
          '(SELECT IFNULL(MIN(display_order), 1) - 1 FROM favorites WHERE folder = ?) ' +
          'FROM favorites WHERE id = ? AND type = ? AND folder = ?',
        [target, target, id, type, source]);
      Database.rdb.executeSync(
        'DELETE FROM favorites WHERE id = ? AND type = ? AND folder = ?', [id, type, source]);
      Database.rdb.commit();
    } catch (error) {
      Database.rdb.rollBack();
      throw new Error(error instanceof Error ? error.message : String(error));
    }
    FavoritesDao.changed();
    return true;
  }

  /** Dart `copy`: same insert as move but keeps the source row. */
  static async copyFavorite(source: string, target: string, id: string, type: number): Promise<boolean> {
    if (await FavoritesDao.isFavoriteIn(target, id, type)) {
      return false;
    }
    Database.rdb.executeSync(
      'INSERT INTO favorites (id, type, source_key, name, author, tags, cover_path, folder, time, display_order) ' +
        'SELECT id, type, source_key, name, author, tags, cover_path, ?, time, ' +
        '(SELECT IFNULL(MIN(display_order), 1) - 1 FROM favorites WHERE folder = ?) ' +
        'FROM favorites WHERE id = ? AND type = ? AND folder = ?',
      [target, target, id, type, source]);
    FavoritesDao.changed();
    return true;
  }

  /** Ids already present in `folder`, queried before any transaction starts. */
  private static async keysIn(folder: string): Promise<string[]> {
    const result = await Database.query(
      'SELECT id, type FROM favorites WHERE folder = ?', [folder]);
    const keys: string[] = [];
    try {
      while (result.goToNextRow()) {
        keys.push(`${result.getLong(result.getColumnIndex('type'))}:` +
          result.getString(result.getColumnIndex('id')));
      }
    } finally {
      result.close();
    }
    return keys;
  }

  static async batchMove(source: string, target: string, items: FavoriteItem[]): Promise<number> {
    if (source === target || items.length === 0) {
      return 0;
    }
    const present = await FavoritesDao.keysIn(target);
    const mine = items.filter((item: FavoriteItem) =>
      present.indexOf(`${item.type.value}:${item.id}`) < 0);
    if (mine.length === 0) {
      return 0;
    }
    let moved = 0;
    Database.rdb.beginTransaction();
    try {
      for (const item of mine) {
        Database.rdb.executeSync(
          'INSERT INTO favorites (id, type, source_key, name, author, tags, cover_path, folder, time, display_order) ' +
            'SELECT id, type, source_key, name, author, tags, cover_path, ?, time, ' +
            '(SELECT IFNULL(MIN(display_order), 1) - 1 FROM favorites WHERE folder = ?) ' +
            'FROM favorites WHERE id = ? AND type = ? AND folder = ?',
          [target, target, item.id, item.type.value, source]);
        Database.rdb.executeSync(
          'DELETE FROM favorites WHERE id = ? AND type = ? AND folder = ?',
          [item.id, item.type.value, source]);
        moved++;
      }
      Database.rdb.commit();
    } catch (error) {
      Database.rdb.rollBack();
      throw new Error(error instanceof Error ? error.message : String(error));
    }
    FavoritesDao.changed();
    return moved;
  }

  static async batchCopy(source: string, target: string, items: FavoriteItem[]): Promise<number> {
    if (items.length === 0) {
      return 0;
    }
    const present = await FavoritesDao.keysIn(target);
    const mine = items.filter((item: FavoriteItem) =>
      present.indexOf(`${item.type.value}:${item.id}`) < 0);
    if (mine.length === 0) {
      return 0;
    }
    let copied = 0;
    Database.rdb.beginTransaction();
    try {
      for (const item of mine) {
        Database.rdb.executeSync(
          'INSERT INTO favorites (id, type, source_key, name, author, tags, cover_path, folder, time, display_order) ' +
            'SELECT id, type, source_key, name, author, tags, cover_path, ?, time, ' +
            '(SELECT IFNULL(MIN(display_order), 1) - 1 FROM favorites WHERE folder = ?) ' +
            'FROM favorites WHERE id = ? AND type = ? AND folder = ?',
          [target, target, item.id, item.type.value, source]);
        copied++;
      }
      Database.rdb.commit();
    } catch (error) {
      Database.rdb.rollBack();
      throw new Error(error instanceof Error ? error.message : String(error));
    }
    FavoritesDao.changed();
    return copied;
  }

  static async batchDelete(folder: string, items: FavoriteItem[]): Promise<void> {
    Database.rdb.beginTransaction();
    try {
      for (const item of items) {
        Database.rdb.executeSync(
          'DELETE FROM favorites WHERE id = ? AND type = ? AND folder = ?',
          [item.id, item.type.value, folder]);
      }
      Database.rdb.commit();
    } catch (error) {
      Database.rdb.rollBack();
      throw new Error(error instanceof Error ? error.message : String(error));
    }
    FavoritesDao.changed();
  }

  /** Dart `reorder`: display_order becomes the list index. */
  static async reorder(folder: string, items: FavoriteItem[]): Promise<void> {
    Database.rdb.beginTransaction();
    try {
      for (let i = 0; i < items.length; i++) {
        Database.rdb.executeSync(
          'UPDATE favorites SET display_order = ? WHERE id = ? AND type = ? AND folder = ?',
          [i, items[i].id, items[i].type.value, folder]);
      }
      Database.rdb.commit();
    } catch (error) {
      Database.rdb.rollBack();
      throw new Error(error instanceof Error ? error.message : String(error));
    }
    FavoritesDao.changed();
  }

  static async count(): Promise<number> {
    const result = await Database.query('SELECT COUNT(*) AS c FROM favorites');
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
