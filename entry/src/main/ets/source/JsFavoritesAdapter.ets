import { Comic, parseComicList } from '../model/Comic';
import { Res } from '../model/Res';
import { FavoriteData } from './ComicSource';
import { JsEngine } from './JsEngine';
import { SourceManager } from './SourceManager';
import { AuthLogScope } from './AuthLogScope';

/** Fixed upstream 7110c19 parser.dart 870–1025. No invented favId JS argument. */
export class JsFavoritesAdapter {
  static create(key: string, scriptPath: string, hasPage: boolean, hasNext: boolean,
    hasFolders: boolean, hasMutation: boolean, multiFolder: boolean): FavoriteData {
    const data = new FavoriteData();
    data.key = key;
    data.title = key;
    data.multiFolder = multiFolder;
    const target = `ComicSource.sources[${JSON.stringify(key)}].favorites`;
    if (hasPage) {
      data.loadComic = (page: number, folder?: string): Promise<Res<Comic[]>> =>
        JsFavoritesAdapter.list(key, scriptPath, `${target}.loadComics(${page},${JSON.stringify(folder ?? null)})`, false);
    }
    if (hasNext) {
      data.loadNext = (next: string | null, folder?: string): Promise<Res<Comic[]>> =>
        JsFavoritesAdapter.list(key, scriptPath, `${target}.loadNext(${JSON.stringify(next)},${JSON.stringify(folder ?? null)})`, true);
    }
    if (multiFolder && hasFolders) {
      data.loadFolders = async (comicId?: string): Promise<Res<Map<string, string>>> => {
        if (!JsFavoritesAdapter.logged(key)) { return Res.fail<Map<string, string>>('请先登录此漫画源'); }
        const scope = AuthLogScope.enter('favorites-folders');
        try {
          const raw = await JsEngine.callJson(`${target}.loadFolders(${JSON.stringify(comicId ?? null)})`, scriptPath);
          if (raw === null || raw === undefined || typeof raw !== 'object' || Array.isArray(raw)) { throw new Error('FOLDERS_RESULT'); }
          const record = raw as Record<string, Object>;
          const foldersRaw = record['folders'];
          if (foldersRaw === null || typeof foldersRaw !== 'object' || Array.isArray(foldersRaw)) { throw new Error('FOLDERS_MAP'); }
          const foldersRecord = foldersRaw as Record<string, Object>;
          const folders = new Map<string, string>();
          for (const id of Object.keys(foldersRecord)) {
            if (typeof foldersRecord[id] !== 'string') { throw new Error('FOLDER_NAME'); }
            folders.set(id, foldersRecord[id] as string);
          }
          const favorited = record['favorited'];
          if (favorited !== undefined && favorited !== null && (!Array.isArray(favorited) ||
            !(favorited as Object[]).every((value: Object) => typeof value === 'string'))) { throw new Error('FOLDER_MEMBERSHIP'); }
          return Res.ok<Map<string, string>>(folders, favorited === null ? undefined : favorited);
        } catch (error) { return Res.fail<Map<string, string>>('网络收藏夹加载失败，请检查登录状态并重试'); }
        finally { AuthLogScope.leave(scope); }
      };
    }
    if (hasMutation) {
      data.addOrDelFavorite = async (comicId: string, folderId: string, isAdding: boolean,
        favId: string | undefined): Promise<Res<boolean>> => {
        if (!JsFavoritesAdapter.logged(key)) { return Res.fail<boolean>('请先登录此漫画源'); }
        const scope = AuthLogScope.enter('favorites-explicit-mutation');
        try {
          // Fixed parser sends three args, but the unchanged installed WN source declares
          // a fourth favoriteId and would otherwise issue a deletion with "undefined".
          // Inspect the declared arity, preserve three-arg sources, and refuse unsafe removal.
          const result = await JsEngine.callJson(`(async()=>{const owner=${target};const f=owner.addOrDelFavorite;` +
            `const favoriteId=${JSON.stringify(favId ?? null)};` +
            `if(!${isAdding}&&f.length>=4&&!favoriteId)return {missingFavoriteId:true};` +
            `if(f.length>=4)await f.call(owner,${JSON.stringify(comicId)},${JSON.stringify(folderId)},${isAdding},favoriteId);` +
            `else await f.call(owner,${JSON.stringify(comicId)},${JSON.stringify(folderId)},${isAdding});return {done:true};})()`, scriptPath);
          if (result !== null && typeof result === 'object' && (result as Record<string, Object>)['missingFavoriteId'] === true) {
            return Res.fail<boolean>('此源移除需要收藏记录ID；请从网络收藏列表选择移除');
          }
          return Res.ok<boolean>(true);
        } catch (error) { return Res.fail<boolean>('网络收藏操作失败；未确认远端状态，请刷新后重试'); }
        finally { AuthLogScope.leave(scope); }
      };
    }
    return data;
  }

  private static logged(key: string): boolean { return SourceManager.find(key)?.isLogged === true; }

  private static async list(key: string, path: string, expression: string, cursor: boolean): Promise<Res<Comic[]>> {
    if (!JsFavoritesAdapter.logged(key)) { return Res.fail<Comic[]>('请先登录此漫画源'); }
    const scope = AuthLogScope.enter('favorites-read');
    try {
      const raw = await JsEngine.callJson(expression, path);
      if (raw === null || raw === undefined || typeof raw !== 'object' || Array.isArray(raw)) { throw new Error('FAVORITES_RESULT'); }
      const record = raw as Record<string, Object>;
      const rows = record['comics'];
      if (!Array.isArray(rows) || !(rows as Object[]).every((value: Object) =>
        value !== null && typeof value === 'object' && !Array.isArray(value))) { throw new Error('FAVORITES_COMICS'); }
      const comics = parseComicList(rows, key);
      if (comics.some((comic: Comic) => comic.id.length === 0)) { throw new Error('FAVORITES_ID'); }
      const sub = cursor ? record['next'] : record['maxPage'];
      if (sub !== undefined && sub !== null) {
        if (cursor && typeof sub !== 'string') { throw new Error('FAVORITES_CURSOR'); }
        if (!cursor && (typeof sub !== 'number' || !Number.isSafeInteger(sub) || (sub as number) < 1)) { throw new Error('FAVORITES_PAGE'); }
      }
      return Res.ok<Comic[]>(comics, sub === null ? undefined : sub);
    } catch (error) { return Res.fail<Comic[]>('网络收藏加载失败，请检查登录状态并重试'); }
    finally { AuthLogScope.leave(scope); }
  }
}
