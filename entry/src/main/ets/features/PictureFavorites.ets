import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { AppContext } from '../foundation/AppContext';
import { PictureFavorite, PictureFavoritesDao } from '../storage/PictureFavoritesDao';
import { ImagePipeline } from '../network/ImagePipeline';
import { ImageRequests } from '../source/ImageRequests';
import { SourceManager } from '../source/SourceManager';

/** Explicit reader action only. Copies final processed bytes, never raw URLs/headers. */
export class PictureFavorites {
  private static busy: Set<string> = new Set<string>();

  static get directory(): string { return `${AppContext.filesDir}/picture_favorites`; }

  static ownedPath(fileName: string): string {
    if (!/^[a-f0-9]{32}\.image$/.test(fileName)) { throw new Error('拒绝操作非图片收藏所有的文件'); }
    return `${PictureFavorites.directory}/${fileName}`;
  }

  static async save(sourceKey: string, comicId: string, epId: string, page: number,
    title: string, imageUrl: string): Promise<void> {
    if (sourceKey.length === 0 || comicId.length === 0 || !Number.isSafeInteger(page) || page < 1 || imageUrl.length === 0) {
      throw new Error('图片收藏需要准确的漫画、章节与页码');
    }
    const key = JSON.stringify([sourceKey, comicId, epId, page]);
    if (PictureFavorites.busy.has(key)) { throw new Error('此页图片收藏正在处理中'); }
    PictureFavorites.busy.add(key);
    let newPath = '';
    let committed = false;
    try {
      const source = SourceManager.find(sourceKey);
      if (source === undefined) { throw new Error('原始漫画源已不可用，不会改用其他源保存'); }
      await PictureFavoritesDao.init();
      if (await PictureFavoritesDao.find(sourceKey, comicId, epId, page) !== undefined) { throw new Error('此页已收藏，请先在图片收藏中移除'); }
      const trace = `picture-favorite-${Date.now()}`;
      const config = await ImageRequests.resolve(source, imageUrl, false, comicId, epId, trace);
      // Shared asynchronous transform/decode pipeline; never save unprocessed scrambled images.
      const bytes = await ImagePipeline.fetch(config, trace);
      if (!fs.accessSync(PictureFavorites.directory)) { fs.mkdirSync(PictureFavorites.directory, true); }
      const row = new PictureFavorite();
      row.sourceKey = sourceKey;
      row.comicId = comicId;
      row.epId = epId;
      row.page = page;
      row.title = title;
      row.createdAt = Date.now();
      row.fileName = `${util.generateRandomUUID(true).replace(/-/g, '').toLowerCase()}.image`;
      newPath = PictureFavorites.ownedPath(row.fileName);
      // API21 OpenMode has no exclusive-create flag; the name is a fresh UUID and
      // an existing file is treated as a collision instead of being overwritten.
      if (fs.accessSync(newPath)) { throw new Error('图片收藏目标文件名冲突，未覆盖已有文件'); }
      const file = await fs.open(newPath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try {
        let offset = 0;
        while (offset < bytes.byteLength) {
          const written = await fs.write(file.fd, bytes.slice(offset));
          if (written <= 0) { throw new Error('图片收藏文件写入不完整'); }
          offset += written;
        }
        await fs.fsync(file.fd);
      } finally { await fs.close(file); }
      await PictureFavoritesDao.put(row);
      committed = true;
    } catch (error) {
      if (!committed && newPath.length > 0 && fs.accessSync(newPath)) { await fs.unlink(newPath); }
      // Do not expose source exceptions containing request URL, account tokens or headers.
      throw new Error(error instanceof Error && /此页已收藏|正在处理中|原始漫画源|准确的漫画/.test(error.message)
        ? error.message : '图片收藏保存失败，请重试；未保存请求地址或账号信息');
    } finally { PictureFavorites.busy.delete(key); }
  }

  /** Caller MUST obtain explicit confirmation. This never deletes downloads/cache/originals. */
  static async remove(row: PictureFavorite, confirmed: boolean): Promise<void> {
    if (!confirmed) { throw new Error('移除图片收藏需要用户确认'); }
    const key = JSON.stringify([row.sourceKey, row.comicId, row.epId, row.page]);
    if (PictureFavorites.busy.has(key)) { throw new Error('此页图片收藏正在处理中'); }
    PictureFavorites.busy.add(key);
    try {
      const current = await PictureFavoritesDao.find(row.sourceKey, row.comicId, row.epId, row.page);
      if (current === undefined || current.fileName !== row.fileName) { throw new Error('图片记录已变化，请刷新'); }
      const owned = PictureFavorites.ownedPath(current.fileName);
      if (fs.accessSync(owned)) {
        if (!fs.statSync(owned).isFile()) { throw new Error('拒绝删除非普通图片收藏文件'); }
        await fs.unlink(owned);
      }
      // If deletion fails, keep the record for a retry. Missing files can have metadata removed.
      await PictureFavoritesDao.remove(current);
    } finally { PictureFavorites.busy.delete(key); }
  }
}
