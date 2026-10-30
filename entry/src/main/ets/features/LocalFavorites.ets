import { ComicType } from '../model/ComicType';
import { FavoriteItem, FavoritesDao } from '../storage/FavoritesDao';
import { FollowUpdate, FollowUpdatesDao } from '../storage/FollowUpdatesDao';
import { FollowUpdates } from './FollowUpdates';
import { Log } from '../foundation/Log';

/**
 * Local favourites are the single user-visible collection; membership also
 * drives update checking. Tracking rows stay internal: one row per
 * (source, comic), created when the comic is favourited and removed only when
 * the last folder membership disappears. Nothing here reads or writes any
 * remote favourite list, download or reading history.
 */
export class LocalFavorites {
  private static migrated: Promise<void> | undefined = undefined;

  /** One upgrade pass per process: old manual-follow rows become favourites. */
  static async ensureMigrated(): Promise<void> {
    if (LocalFavorites.migrated === undefined) {
      LocalFavorites.migrated = LocalFavorites.migrate().catch((error: Error) => {
        LocalFavorites.migrated = undefined;
        throw error;
      });
    }
    return LocalFavorites.migrated;
  }

  private static async migrate(): Promise<void> {
    await FollowUpdatesDao.init();
    let rows: FollowUpdate[] = [];
    try { rows = await FollowUpdatesDao.list(); }
    catch (error) { Log.warn('LocalFavorites', 'old follow list unavailable; nothing migrated'); return; }
    let converted = 0;
    for (let i = 0; i < rows.length; i++) {
      const row = rows[i];
      if (row.sourceKey.length === 0 || row.comicId.length === 0) { continue; }
      const type = ComicType.fromKey(row.sourceKey).value;
      try {
        if (await FavoritesDao.isFavorite(row.comicId, type)) { continue; }
        const item = new FavoriteItem();
        item.id = row.comicId;
        item.type = ComicType.fromKey(row.sourceKey);
        item.sourceKey = row.sourceKey;
        item.name = row.title.length > 0 ? row.title : row.comicId;
        item.author = '';
        item.tags = [];
        item.coverPath = row.cover;
        item.folder = '';
        item.time = FavoriteItem.now();
        item.syncComicFields();
        if (await FavoritesDao.add(item)) { converted++; }
      } catch (error) { Log.warn('LocalFavorites', 'one old follow row could not become a favorite'); }
    }
    if (converted > 0) { Log.info('LocalFavorites', `migrated ${converted} old follow item(s) into local favorites`); }
  }

  /** Favouriting also enables manual update checks for that comic. */
  static async track(sourceKey: string, comicId: string, title: string, cover: string): Promise<void> {
    if (sourceKey.length === 0 || comicId.length === 0) { return; }
    try { await FollowUpdatesDao.follow(sourceKey, comicId, title, cover); }
    catch (error) { Log.warn('LocalFavorites', 'update tracking could not be enabled'); }
  }

  /** Stop tracking only once no folder still holds the comic. */
  static async syncRemoval(sourceKey: string, comicId: string, type: number): Promise<void> {
    if (comicId.length === 0) { return; }
    try {
      if (await FavoritesDao.isFavorite(comicId, type)) { return; }
      await FollowUpdatesDao.unfollow(sourceKey, comicId);
    } catch (error) { Log.warn('LocalFavorites', 'update tracking could not be cleared'); }
  }

  /** Manual foreground check over the local-favourite set; never scheduled. */
  static async checkUpdates(onResult: (row: FollowUpdate) => void = (row: FollowUpdate): void => {},
    shouldContinue: () => boolean = (): boolean => true): Promise<void> {
    await LocalFavorites.ensureMigrated();
    await FollowUpdates.checkAll(onResult, shouldContinue);
  }
}
