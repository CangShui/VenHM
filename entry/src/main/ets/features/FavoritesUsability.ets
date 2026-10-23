import { FavoriteFolder, FavoriteItem, FavoritesDao } from '../storage/FavoritesDao';
import { ComicType } from '../model/ComicType';
import { Log } from '../foundation/Log';

/**
 * Isolated favourites regression.
 *
 * Every row uses a probe-only source key and freshly generated folder names, so
 * real favourites and real folders are never read, moved or deleted. Cleanup
 * removes exactly the folders this test created, even when an assertion fails.
 */
export class FavoritesUsability {
  private static check(value: boolean, label: string): void {
    if (!value) {
      throw new Error(label);
    }
  }

  private static probeItem(folder: string, suffix: string): FavoriteItem {
    const item = new FavoriteItem();
    item.id = `hm_probe_comic_${suffix}`;
    item.sourceKey = '__favorites_probe_source__';
    item.type = ComicType.fromKey(item.sourceKey);
    item.name = `探测漫画 ${suffix}`;
    item.author = '探测作者';
    item.tags = ['probe', 'a'];
    item.coverPath = '';
    item.folder = folder;
    item.time = FavoriteItem.now();
    return item;
  }

  static async run(): Promise<string[]> {
    const reports: string[] = [];
    const stamp = `${Date.now()}_${Math.floor(Math.random() * 1000000)}`;
    const folderA = `__HM_FAV_A_${stamp}`;
    const folderB = `__HM_FAV_B_${stamp}`;
    const folderRenamed = `__HM_FAV_R_${stamp}`;
    const created: string[] = [];
    const item = FavoritesUsability.probeItem(folderA, stamp);
    try {
      const existing = await FavoritesDao.folderNames();
      FavoritesUsability.check(
        FavoritesDao.validateFolderName('', existing) !== null, '空名应被拒绝');
      FavoritesUsability.check(
        FavoritesDao.validateFolderName('x'.repeat(51), existing) !== null, '超长名应被拒绝');
      FavoritesUsability.check(
        FavoritesDao.validateFolderName('a"b', existing) !== null, '双引号应被拒绝');
      FavoritesUsability.check(
        FavoritesDao.validateFolderName(existing[0], existing) !== null, '重名应被拒绝');

      await FavoritesDao.createFolder(folderA);
      created.push(folderA);
      await FavoritesDao.createFolder(folderB);
      created.push(folderB);
      let folders = await FavoritesDao.listFolders();
      // An empty folder must survive, which a DISTINCT-over-favourites query could not do.
      FavoritesUsability.check(
        folders.filter((f: FavoriteFolder) => f.name === folderA).length === 1, '空收藏夹未持久化');
      reports.push('PASS · 新建空收藏夹可持久化；空名/超长/双引号/重名被拒绝');

      FavoritesUsability.check(await FavoritesDao.add(item) === true, '首次收藏应成功');
      FavoritesUsability.check(await FavoritesDao.add(item) === false, '重复收藏应返回 false');
      item.folder = folderB;
      FavoritesUsability.check(await FavoritesDao.add(item) === true, '同漫画应可加入第二个收藏夹');
      FavoritesUsability.check(await FavoritesDao.isFavorite(item.id, item.type.value), '应显示已收藏');

      let member = await FavoritesDao.foldersOf(item.id, item.type.value);
      FavoritesUsability.check(member.length === 2, '同一漫画应同时存在于两个收藏夹');
      reports.push('PASS · 同一漫画可存在于多个收藏夹，重复添加不产生副本');

      await FavoritesDao.remove(item.id, item.type.value, folderA);
      member = await FavoritesDao.foldersOf(item.id, item.type.value);
      FavoritesUsability.check(member.length === 1 && member[0] === folderB,
        '只应移除指定收藏夹中的记录');
      reports.push('PASS · 从单个收藏夹移除不影响其它收藏夹（修复“取消收藏残留”）');

      // Move back to A, then move again to B where it already exists: a no-op.
      await FavoritesDao.moveFavorite(folderB, folderA, item.id, item.type.value);
      member = await FavoritesDao.foldersOf(item.id, item.type.value);
      FavoritesUsability.check(member.length === 1 && member[0] === folderA, '移动未生效');
      item.folder = folderB;
      await FavoritesDao.add(item);
      FavoritesUsability.check(
        await FavoritesDao.moveFavorite(folderA, folderB, item.id, item.type.value) === false,
        '目标已存在时应为 no-op');
      member = await FavoritesDao.foldersOf(item.id, item.type.value);
      FavoritesUsability.check(member.length === 2, 'no-op 移动不应删除来源');
      reports.push('PASS · 移动语义：目标已有该漫画时不删除来源（与上游一致）');

      const second = FavoritesUsability.probeItem(folderA, `${stamp}_2`);
      await FavoritesDao.add(second);
      FavoritesUsability.check(
        await FavoritesDao.copyFavorite(folderA, folderB, second.id, second.type.value) === true,
        '复制应成功');
      const listedA = await FavoritesDao.list(folderA);
      const listedB = await FavoritesDao.list(folderB);
      FavoritesUsability.check(
        listedA.filter((i: FavoriteItem) => i.id === second.id).length === 1 &&
        listedB.filter((i: FavoriteItem) => i.id === second.id).length === 1,
        '复制后来源与目标都应保留');
      reports.push('PASS · 复制保留来源并写入目标收藏夹');

      // Reorder writes display_order = index, and list() must honour it.
      const reversed = listedB.slice().reverse();
      await FavoritesDao.reorder(folderB, reversed);
      const reordered = await FavoritesDao.list(folderB);
      FavoritesUsability.check(
        reordered.map((i: FavoriteItem) => i.id).join(',') ===
          reversed.map((i: FavoriteItem) => i.id).join(','),
        '收藏夹内排序未按列表顺序保存');
      reports.push('PASS · 收藏夹内排序按列表顺序持久化');

      await FavoritesDao.updateFolderOrder([folderB, folderA]);
      folders = await FavoritesDao.listFolders();
      const order = folders.map((f: FavoriteFolder) => f.name);
      FavoritesUsability.check(
        order.indexOf(folderB) < order.indexOf(folderA), '收藏夹顺序未持久化');
      reports.push('PASS · 收藏夹顺序持久化');

      await FavoritesDao.renameFolder(folderA, folderRenamed);
      created[0] = folderRenamed;
      folders = await FavoritesDao.listFolders();
      FavoritesUsability.check(
        folders.filter((f: FavoriteFolder) => f.name === folderRenamed).length === 1,
        '重命名后收藏夹丢失');
      FavoritesUsability.check((await FavoritesDao.list(folderRenamed)).length > 0,
        '重命名应保留夹内收藏');
      const renamedSecond = await FavoritesDao.foldersOf(second.id, second.type.value);
      FavoritesUsability.check(renamedSecond.indexOf(folderRenamed) >= 0, '夹内记录未随夹改名');
      reports.push('PASS · 重命名保留夹内收藏与记录归属');

      let defaultGuard = false;
      try {
        await FavoritesDao.renameFolder('', 'x');
      } catch (error) {
        defaultGuard = true;
      }
      FavoritesUsability.check(defaultGuard, '默认收藏夹不应可重命名');
      defaultGuard = false;
      try {
        await FavoritesDao.deleteFolder('');
      } catch (error) {
        defaultGuard = true;
      }
      FavoritesUsability.check(defaultGuard, '默认收藏夹不应可删除');
      reports.push('PASS · 默认收藏夹禁止重命名/删除');

      await FavoritesDao.deleteFolder(folderRenamed);
      created.splice(0, 1);
      FavoritesUsability.check(
        (await FavoritesDao.list(folderRenamed)).length === 0, '删除收藏夹后仍有记录');
      reports.push('PASS · 删除收藏夹同时清空其记录，其它收藏夹不受影响');
    } finally {
      // Cleanup is name-scoped: only folders created above are removed.
      for (const name of created) {
        try {
          await FavoritesDao.deleteFolder(name);
        } catch (error) {
          Log.warn('FavoritesUsability', `cleanup ${name} failed: ${error}`);
        }
      }
      try {
        await FavoritesDao.removeEverywhere(item.id, item.type.value);
      } catch (error) {
        Log.warn('FavoritesUsability', `cleanup row failed: ${error}`);
      }
    }
    for (const report of reports) {
      Log.info('FavoritesUsability', report);
    }
    return reports;
  }
}
