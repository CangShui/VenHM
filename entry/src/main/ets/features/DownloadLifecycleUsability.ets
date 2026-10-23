import { DownloadQueue } from './DownloadQueue';
import { HistoryUsability } from './HistoryUsability';
import { ComicSource } from '../source/ComicSource';
import { SourceManager } from '../source/SourceManager';
import { ComicChapters } from '../model/Comic';
import { ComicDetails } from '../model/ComicDetails';
import { Res } from '../model/Res';
import { HttpClient, HttpRequestOptions } from '../network/HttpClient';
import { http } from '@kit.NetworkKit';
import { Log } from '../foundation/Log';

/** Two-step, explicitly initiated OS background probe with an owned synthetic task. */
export class DownloadLifecycleUsability {
  private static taskId: string = '';
  private static sourceKey: string = '';
  private static hadFixture: boolean = false;
  private static pending?: Promise<void>;
  private static failure: string = '';

  static async prepare(): Promise<string[]> {
    if (DownloadLifecycleUsability.taskId.length > 0) { throw new Error('已有后台暂停验收，请先复核清理'); }
    DownloadQueue.init();
    if (DownloadQueue.tasks.some((task) => task.status === 'running' || task.status === 'checking')) {
      throw new Error('真实下载正在执行，不进行隔离后台测试');
    }
    const trace = `download-lifecycle-probe-${Date.now()}`;
    const options = new HttpRequestOptions();
    options.traceId = trace; options.retries = 0; options.connectTimeoutMs = 3000; options.readTimeoutMs = 3000;
    const health = await HttpClient.request('http://127.0.0.1:29091/health', http.RequestMethod.GET, options);
    if (!health.ok || health.body !== '{"fixture":"venera-hm-image-v1"}') { throw new Error('需要CLI本机fixture服务器；未创建任何任务'); }
    DownloadLifecycleUsability.hadFixture = HistoryUsability.fixtureId().length > 0;
    const sample = await HistoryUsability.prepareFixture();
    const key = `__HM_DOWNLOAD_LIFE_${Date.now()}_${Math.floor(Math.random() * 1000000000)}`;
    const source = new ComicSource(key, '隔离后台暂停验收');
    source.version = '1.0.0';
    const details = new ComicDetails();
    details.title = '隔离慢响应下载'; details.comicId = sample.id; details.sourceKey = key; details.cover = sample.cover;
    details.chapters = ComicChapters.flatOf(new Map<string, string>([['1', '慢响应验收']]));
    source.loadComicInfo = async (): Promise<Res<ComicDetails>> => new Res<ComicDetails>(details);
    source.loadComicPages = async (): Promise<Res<string[]>> => new Res<string[]>(['http://127.0.0.1:29091/slow']);
    SourceManager.register(source);
    DownloadLifecycleUsability.sourceKey = key;
    try {
      const task = await DownloadQueue.add(key, sample.id);
      DownloadLifecycleUsability.taskId = task.id;
      DownloadLifecycleUsability.failure = '';
      DownloadLifecycleUsability.pending = DownloadQueue.resume(task.id).catch((error: Object): void => {
        DownloadLifecycleUsability.failure = String(error);
      });
      Log.audit(trace, '后台验收准备返回', `任务=${task.id}；只访问本机20秒慢响应；请实际退后台，再回到此页复核`);
      return ['READY · 隔离慢响应下载已开始，请实际退后台后回到此页，点“复核并清理后台暂停验收”'];
    } catch (error) {
      SourceManager.unregister(key);
      if (!DownloadLifecycleUsability.hadFixture) { await HistoryUsability.cleanupFixture(); }
      throw new Error(String(error));
    }
  }

  static async finish(): Promise<string[]> {
    const id = DownloadLifecycleUsability.taskId;
    if (id.length === 0) { throw new Error('当前进程没有后台验收任务；不猜测或清理其他下载'); }
    await DownloadLifecycleUsability.pending;
    try {
      const task = DownloadQueue.tasks.find((item) => item.id === id);
      if (task === undefined || task.status !== 'paused' || task.savedPages !== 0 || task.page !== 0 ||
        DownloadLifecycleUsability.failure.length > 0) {
        throw new Error(`后台暂停验收未通过；状态=${task?.status ?? 'missing'}，页数=${task?.savedPages ?? -1}`);
      }
      Log.audit(id, '后台验收复核返回', 'PASS · 真实退后台后保持paused，晚到响应未写页，回前台未自动恢复');
      return ['PASS · 实际退后台暂停、晚到响应不落盘、回前台不自动联网；隔离任务已清理'];
    } finally {
      DownloadQueue.cancel(id);
      DownloadQueue.cleanupProbe(id);
      SourceManager.unregister(DownloadLifecycleUsability.sourceKey);
      DownloadLifecycleUsability.taskId = ''; DownloadLifecycleUsability.sourceKey = '';
      DownloadLifecycleUsability.pending = undefined;
      if (!DownloadLifecycleUsability.hadFixture) { await HistoryUsability.cleanupFixture(); }
    }
  }
}
