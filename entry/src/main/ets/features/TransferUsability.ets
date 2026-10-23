import { DownloadQueue } from './DownloadQueue';
import { HistoryUsability } from './HistoryUsability';
import { DataSync, SyncSnapshot, SyncTable } from './DataSync';
import { Database } from '../storage/Database';
import { Settings } from '../foundation/Settings';
import { Log } from '../foundation/Log';
import { fileIo as fs } from '@kit.CoreFileKit';
import { AppContext } from '../foundation/AppContext';

/** Isolated real-device filesystem/SQL regression. Never uploads user data. */
export class TransferUsability {
  static async download(): Promise<string[]> {
    const trace = `download-probe-${Date.now()}`;
    const hadFixture = HistoryUsability.fixtureId().length > 0;
    const sample = await HistoryUsability.prepareFixture();
    const task = await DownloadQueue.add('local', sample.id);
    try {
      await DownloadQueue.resume(task.id);
      if (task.status !== 'completed' || task.savedPages !== 6 || task.chapter !== 2) {
        throw new Error('本地样本6页下载未全部完成');
      }
      const folder = `${AppContext.localComicDir}/${task.id}`;
      const first = `${folder}/0001/000001.png`;
      const last = `${folder}/0002/000003.png`;
      if (!fs.accessSync(first) || !fs.accessSync(last)) { throw new Error('下载首末页文件不存在'); }
      await DownloadQueue.resume(task.id);
      if (task.status !== 'completed' || task.savedPages !== 6) { throw new Error('已完成下载磁盘复核失败'); }
      // This random, owned diagnostics directory is safe to inject one missing file.
      const owner = JSON.parse(fs.readTextSync(`${folder}/download.json`)) as Record<string, Object>;
      if (owner['owner'] !== task.id) { throw new Error('缺页测试目录所有权不符，未删除任何文件'); }
      fs.unlinkSync(last);
      Log.audit(trace, '下载缺页注入', '仅删除本次随机验收下载的最后一页；实际漫画目录不变');
      await DownloadQueue.resume(task.id);
      if (!fs.accessSync(last) || task.status !== 'completed' || task.savedPages !== 6) {
        throw new Error('检查点缺页未恢复或累计页数重复');
      }
      const ledger = JSON.parse(fs.readTextSync(`${AppContext.filesDir}/downloads.json`)) as Object[];
      if (!ledger.some((item: Object) => (item as Record<string, Object>)['id'] === task.id &&
          (item as Record<string, Object>)['status'] === 'completed')) {
        throw new Error('下载状态未落盘');
      }
      Log.audit(trace, '下载验收通过', '本地2章×3页真实图片解码/原子写入；完成复核、缺页回退恢复、累计6页；状态读回completed');
      return ['PASS · 本地2章×3页已解码下载，完成复核与缺页恢复通过，完成检查点已落盘'];
    } finally {
      DownloadQueue.cleanupProbe(task.id);
      if (!hadFixture) { await HistoryUsability.cleanupFixture(); }
      Log.audit(trace, '下载验收清理', '仅清理本次隔离下载；已有阅读样本保留');
    }
  }

  static async sync(): Promise<string[]> {
    const trace = `sync-probe-${Date.now()}`;
    const folder = `__HM_SYNC_PROBE_${Date.now()}_${Math.floor(Math.random() * 1000000000)}`;
    const rows = await Database.query('SELECT COUNT(*) FROM favorite_folders WHERE name = ?', [folder]);
    try { if (!rows.goToFirstRow() || rows.getLong(0) !== 0) { throw new Error('验收文件夹标识冲突'); } }
    finally { rows.close(); }
    try {
      const backup = new SyncSnapshot();
      const table = new SyncTable();
      table.name = 'favorite_folders';
      table.columns = ['name', 'display_order'];
      table.rows = [[folder, 99999]];
      backup.tables = [table];
      DataSync.mergeSnapshot(backup, trace);
      DataSync.mergeSnapshot(backup, trace);
      const found = await Database.query('SELECT COUNT(*) FROM favorite_folders WHERE name = ?', [folder]);
      try { if (!found.goToFirstRow() || found.getLong(0) !== 1) { throw new Error('重复合并未正确去重'); } }
      finally { found.close(); }
      const snapshot = await DataSync.exportSnapshot(trace);
      if (snapshot.tables.length !== 3 || snapshot.tables.some((table) =>
          table.name === 'source_data' || table.name === 'cookies')) {
        throw new Error('备份白名单未隔离凭据数据');
      }
      Log.audit(trace, '同步验收通过', '真实数据库重复合并不新增副本；备份只含历史与收藏；无网络上传');
      return ['PASS · 同步白名单导出、真实RDB重复合并去重；没有上传任何数据',
        '待验收 · 用户WebDAV服务器的PUT/GET、真实认证、跨设备冲突同步'];
    } finally {
      await Database.execute('DELETE FROM favorite_folders WHERE name = ?', [folder]);
      Log.audit(trace, '同步验收清理', '只删除随机命名的同步测试收藏夹，用户记录不变');
    }
  }
}
