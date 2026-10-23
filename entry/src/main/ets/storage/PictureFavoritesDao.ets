import { Database } from './Database';

export class PictureFavorite {
  sourceKey: string = '';
  comicId: string = '';
  epId: string = '';
  page: number = 1;
  title: string = '';
  fileName: string = '';
  createdAt: number = 0;
}

/** Own table only. No migrations to history, local favorites or download data. */
export class PictureFavoritesDao {
  static async init(): Promise<void> {
    await Database.init();
    await Database.execute('CREATE TABLE IF NOT EXISTS picture_favorites (' +
      'source_key TEXT NOT NULL, comic_id TEXT NOT NULL, ep_id TEXT NOT NULL, page INTEGER NOT NULL, ' +
      'title TEXT NOT NULL, file_name TEXT NOT NULL, created_at INTEGER NOT NULL, ' +
      'PRIMARY KEY (source_key, comic_id, ep_id, page))');
  }

  static async list(): Promise<PictureFavorite[]> {
    await PictureFavoritesDao.init();
    const result = await Database.query('SELECT * FROM picture_favorites ORDER BY created_at DESC');
    const rows: PictureFavorite[] = [];
    try {
      while (result.goToNextRow()) {
        const row = new PictureFavorite();
        row.sourceKey = result.getString(result.getColumnIndex('source_key'));
        row.comicId = result.getString(result.getColumnIndex('comic_id'));
        row.epId = result.getString(result.getColumnIndex('ep_id'));
        row.page = result.getLong(result.getColumnIndex('page'));
        row.title = result.getString(result.getColumnIndex('title'));
        row.fileName = result.getString(result.getColumnIndex('file_name'));
        row.createdAt = result.getLong(result.getColumnIndex('created_at'));
        rows.push(row);
      }
    } finally { result.close(); }
    return rows;
  }

  static async find(sourceKey: string, comicId: string, epId: string, page: number): Promise<PictureFavorite | undefined> {
    const rows = await PictureFavoritesDao.list();
    return rows.find((row: PictureFavorite) => row.sourceKey === sourceKey && row.comicId === comicId && row.epId === epId && row.page === page);
  }

  static async put(row: PictureFavorite): Promise<void> {
    await PictureFavoritesDao.init();
    await Database.execute('INSERT OR REPLACE INTO picture_favorites ' +
      '(source_key,comic_id,ep_id,page,title,file_name,created_at) VALUES (?,?,?,?,?,?,?)',
      [row.sourceKey, row.comicId, row.epId, row.page, row.title, row.fileName, row.createdAt]);
  }

  static async remove(row: PictureFavorite): Promise<void> {
    await PictureFavoritesDao.init();
    await Database.execute('DELETE FROM picture_favorites WHERE source_key=? AND comic_id=? AND ep_id=? AND page=? AND file_name=?',
      [row.sourceKey, row.comicId, row.epId, row.page, row.fileName]);
  }
}
