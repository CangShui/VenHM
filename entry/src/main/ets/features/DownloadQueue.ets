import { fileIo as fs } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { AppContext } from '../foundation/AppContext';
import { Log } from '../foundation/Log';
import { ComicSource } from '../source/ComicSource';
import { SourceManager } from '../source/SourceManager';
import { ImageRequests } from '../source/ImageRequests';
import { ImagePipeline } from '../network/ImagePipeline';
import { ImageTransforms } from '../network/ImageTransforms';
import { BackgroundDownloadCoordinator } from './BackgroundDownloadCoordinator';

export class DownloadTask {
  id: string = '';
  sourceKey: string = '';
  comicId: string = '';
  title: string = '';
  status: string = 'paused';
  chapterIds: string[] = [];
  chapterTitles: string[] = [];
  chapter: number = 0;
  page: number = 0;
  savedPages: number = 0;
  currentChapterPages: number = 0;
  chapterPageCounts: number[] = [];
  error: string = '';
  /** Waiting for a free concurrency slot. Never implies any network activity. */
  queued: boolean = false;
}

/** Immutable snapshot for one task's progress bar. totalPages is 0 while the page total is unknown. */
export class DownloadProgress {
  savedPages: number = 0;
  totalPages: number = 0;
  knownChapters: number = 0;
  totalChapters: number = 0;
  currentChapter: number = 0;
  currentChapterPages: number = 0;
  /** Chapter/page weighted completion, floored and clamped to 0..100. Never decreases in one run. */
  percent: number = 0;
  /** True while the page total of the whole task is not known yet; the percent is chapter based. */
  indeterminate: boolean = true;
}

/** Result of one page worker inside a parallel batch; never a rejected promise. */
class PageOutcome {
  saved: boolean = false;
  error: string = '';
}

/**
 * Task queue with bounded concurrency:
 * - at most MAX_CONCURRENT_TASKS tasks download at the same time, the rest wait for a slot;
 * - inside a chapter at most PAGE_WORKERS pages are fetched at the same time;
 * - the persisted checkpoint stays a CONTIGUOUS prefix: page N is only recorded after every
 *   page before it in the same batch was verified and atomically renamed;
 * - one real native background lease is shared, the other running tasks fall back to foreground.
 */
export class DownloadQueue {
  static tasks: DownloadTask[] = [];
  /** Hard cap on simultaneously downloading tasks; further resumes wait for a free slot. */
  static readonly MAX_CONCURRENT_TASKS: number = 3;
  /** Bounded worker pool for the pages of one chapter. */
  static readonly PAGE_WORKERS: number = 3;

  private static initialized: boolean = false;
  private static foreground: boolean = true;
  /** Task id that currently owns (or is negotiating) the single native background lease. */
  private static leaseOwner: string = '';
  private static slotWaiters: (() => void)[] = [];
  private static readonly adding: Map<string, Promise<DownloadTask>> = new Map<string, Promise<DownloadTask>>();
  private static readonly generations: Map<string, number> = new Map<string, number>();
  private static readonly inflight: Map<string, Promise<void>> = new Map<string, Promise<void>>();
  private static readonly mutating: Set<string> = new Set<string>();
  /** Admitted runners by task id, with the generation that owns the slot. */
  private static readonly running: Map<string, number> = new Map<string, number>();

  private static invalidate(id: string): number {
    const generation = (DownloadQueue.generations.get(id) ?? 0) + 1;
    DownloadQueue.generations.set(id, generation);
    ImageTransforms.cancel(id);
    // A queued resume must observe the new generation immediately instead of waiting for a slot.
    DownloadQueue.wakeSlots();
    return generation;
  }

  private static live(task: DownloadTask, generation: number): boolean {
    return DownloadQueue.generations.get(task.id) === generation && DownloadQueue.tasks.includes(task) &&
      (task.status === 'starting' || task.status === 'checking' || task.status === 'running') &&
      (DownloadQueue.foreground || BackgroundDownloadCoordinator.held(task.id));
  }

  /** Still wanted: same generation, still in the queue, not cancelled. Used before a slot is granted. */
  private static queued(task: DownloadTask, generation: number): boolean {
    return DownloadQueue.generations.get(task.id) === generation && DownloadQueue.tasks.includes(task) &&
      task.status !== 'cancelled';
  }

  private static wakeSlots(): void {
    const waiters = DownloadQueue.slotWaiters;
    DownloadQueue.slotWaiters = [];
    for (const resolve of waiters) { resolve(); }
  }

  private static waitSlot(): Promise<void> {
    return new Promise<void>((resolve: () => void) => { DownloadQueue.slotWaiters.push(resolve); });
  }

  private static releaseSlot(id: string): void {
    DownloadQueue.running.delete(id);
    DownloadQueue.wakeSlots();
  }

  /**
   * Progress snapshot. The percentage is chapter weighted (completed chapters plus the fraction of
   * the current chapter) so it stays monotonic while chapter page counts are still being discovered.
   * totalPages is only reported once every chapter's page count is known; otherwise it stays 0 and
   * indeterminate is true instead of inventing a total.
   */
  static progress(task: DownloadTask): DownloadProgress {
    const progress = new DownloadProgress();
    const totalChapters = task.chapterIds.length;
    progress.totalChapters = totalChapters;
    progress.savedPages = task.savedPages;
    progress.currentChapter = Math.min(task.chapter + 1, totalChapters);
    progress.currentChapterPages = task.currentChapterPages;
    let knownChapters = 0;
    let knownPages = 0;
    for (let index = 0; index < totalChapters; index++) {
      const count = task.chapterPageCounts[index];
      if (typeof count === 'number' && Number.isSafeInteger(count) && count > 0) {
        knownChapters++;
        knownPages += count;
      }
    }
    progress.knownChapters = knownChapters;
    if (totalChapters > 0 && knownChapters === totalChapters) {
      progress.totalPages = knownPages;
    } else {
      progress.totalPages = 0;
    }
    progress.indeterminate = progress.totalPages === 0;
    let numerator = task.chapter;
    if (task.chapter < totalChapters && task.currentChapterPages > 0) {
      numerator += Math.min(task.page, task.currentChapterPages) / task.currentChapterPages;
    }
    let percent = 0;
    if (totalChapters > 0) { percent = Math.floor((numerator / totalChapters) * 100); }
    if (percent < 0) { percent = 0; }
    if (percent > 100) { percent = 100; }
    progress.percent = percent;
    return progress;
  }

  static backgroundStatus(id: string): string {
    if (BackgroundDownloadCoordinator.held(id)) { return '系统后台数据传输已接受（持续通知）'; }
    if (DownloadQueue.leaseOwner.length > 0 && DownloadQueue.leaseOwner !== id &&
      BackgroundDownloadCoordinator.held(DownloadQueue.leaseOwner)) {
      return '后台数据传输租约由另一并行任务持有；本任务仅前台下载';
    }
    return BackgroundDownloadCoordinator.error || '后台服务未运行';
  }

  private static stopService(task?: DownloadTask): Promise<void> {
    return BackgroundDownloadCoordinator.stop().catch((error: Object) => {
      const message = error instanceof Error ? error.message : String(error);
      if (task !== undefined && DownloadQueue.tasks.includes(task)) {
        task.error = message; DownloadQueue.persist();
      }
      Log.audit('downloads-background', '后台服务停止失败', 'phase=native-stop；具体错误见后台状态');
      throw new Error(message);
    });
  }

  private static folder(id: string): string {
    if (!/^DL_[0-9]+_[0-9]+$/.test(id)) {
      throw new Error('拒绝操作非下载任务目录');
    }
    const root = AppContext.localComicDir;
    if (!root.startsWith('/') || root.includes('\\') || root.split('/').some((part: string) => part === '..' || part === '.') ||
      root !== `${AppContext.filesDir}/local_comics`) { throw new Error('下载根目录无效'); }
    for (const path of [AppContext.filesDir, root, `${root}/${id}`]) {
      if (fs.accessSync(path) && fs.lstatSync(path).isSymbolicLink()) { throw new Error('拒绝操作符号链接下载目录'); }
    }
    return `${root}/${id}`;
  }

  private static ownedFolder(id: string): string {
    const dir = DownloadQueue.folder(id);
    const markerPath = `${dir}/download.json`;
    if (fs.lstatSync(markerPath).isSymbolicLink() || !fs.statSync(markerPath).isFile()) {
      throw new Error('下载目录所有权标记不是普通文件');
    }
    const marker = JSON.parse(fs.readTextSync(markerPath)) as Record<string, Object>;
    if (marker['owner'] !== id) { throw new Error('下载目录所有权不匹配'); }
    return dir;
  }

  /** Validate the entire owned tree before invoking SDK recursive deletion (no symlink escape). */
  private static validateTree(path: string, root: string): void {
    if (path !== root && !path.startsWith(`${root}/`)) { throw new Error('下载目录越界'); }
    if (fs.lstatSync(path).isSymbolicLink()) { throw new Error('下载目录含符号链接，未删除'); }
    if (!fs.statSync(path).isDirectory()) { return; }
    for (const name of fs.listFileSync(path)) {
      if (name === '.' || name === '..' || name.includes('/') || name.includes('\\')) { throw new Error('下载目录包含无效文件名'); }
      DownloadQueue.validateTree(`${path}/${name}`, root);
    }
  }

  private static cleanParts(id: string): void {
    const dir = DownloadQueue.ownedFolder(id);
    for (const chapter of fs.listFileSync(dir)) {
      if (!/^[0-9]{4,}$/.test(chapter)) { continue; }
      const chapterDir = `${dir}/${chapter}`;
      if (fs.lstatSync(chapterDir).isSymbolicLink() || !fs.statSync(chapterDir).isDirectory()) {
        throw new Error('下载章节路径不是自有普通目录');
      }
      for (const name of fs.listFileSync(chapterDir)) {
        if (!/^[0-9]{6,}[.](png|jpg|webp|gif|bmp)[.]part$/.test(name)) { continue; }
        const path = `${chapterDir}/${name}`;
        if (fs.lstatSync(path).isSymbolicLink() || !fs.statSync(path).isFile()) { throw new Error('下载临时页不是普通文件'); }
        // The complete absolute path was checked against owned root + strict chapter/page names.
        fs.unlinkSync(path);
      }
    }
  }

  private static ledger(): string { return `${AppContext.filesDir}/downloads.json`; }

  static init(): void {
    if (DownloadQueue.initialized) { return; }
    const path = DownloadQueue.ledger();
    if (fs.accessSync(path)) {
      const raw = JSON.parse(fs.readTextSync(path)) as Object;
      if (!Array.isArray(raw)) { throw new Error('下载任务记录格式错误；未覆盖原文件'); }
      const restored: DownloadTask[] = [];
      for (const item of raw as Object[]) {
        const value = item as Record<string, Object>;
        const id = value['id'];
        if (typeof id !== 'string' || !/^DL_[0-9]+_[0-9]+$/.test(id)) { continue; }
        const task = new DownloadTask();
        task.id = id;
        task.sourceKey = typeof value['sourceKey'] === 'string' ? value['sourceKey'] as string : '';
        task.comicId = typeof value['comicId'] === 'string' ? value['comicId'] as string : '';
        task.title = typeof value['title'] === 'string' ? value['title'] as string : '';
        task.chapterIds = Array.isArray(value['chapterIds']) ? value['chapterIds'] as string[] : [];
        task.chapterTitles = Array.isArray(value['chapterTitles']) ? value['chapterTitles'] as string[] : [];
        task.chapter = typeof value['chapter'] === 'number' ? value['chapter'] as number : 0;
        task.page = typeof value['page'] === 'number' ? value['page'] as number : 0;
        task.savedPages = typeof value['savedPages'] === 'number' ? value['savedPages'] as number : 0;
        task.chapterPageCounts = Array.isArray(value['chapterPageCounts']) ? value['chapterPageCounts'] as number[] : [];
        task.currentChapterPages = typeof value['currentChapterPages'] === 'number' ? value['currentChapterPages'] as number : 0;
        task.status = value['status'] === 'completed' ? 'completed' : value['status'] === 'cancelled' ? 'cancelled' : 'paused';
        // A restored task never inherits a queue slot or an active status.
        task.queued = false;
        if (!DownloadQueue.validTask(task)) {
          task.status = 'failed'; task.error = '下载记录字段/检查点无效，未继续写入';
        } else if (task.status === 'completed' && task.chapterPageCounts.length !== task.chapterIds.length) {
          task.status = 'paused'; task.error = '旧版任务缺少每章页数，继续时从可验证检查点重建；原文件保留';
        }
        restored.push(task);
      }
      DownloadQueue.tasks = restored;
    }
    DownloadQueue.initialized = true;
    Log.audit('downloads-init', '下载恢复', `任务数=${DownloadQueue.tasks.length}；中断任务暂停，不自动联网`);
  }

  private static validTask(task: DownloadTask): boolean {
    return task.sourceKey.length > 0 && task.comicId.length > 0 && task.chapterIds.length > 0 &&
      task.chapterIds.every((id: string) => typeof id === 'string') &&
      task.chapterTitles.length === task.chapterIds.length &&
      task.chapterTitles.every((title: string) => typeof title === 'string') &&
      Number.isSafeInteger(task.chapter) && task.chapter >= 0 && task.chapter <= task.chapterIds.length &&
      Number.isSafeInteger(task.page) && task.page >= 0 && (task.chapter < task.chapterIds.length || task.page === 0) &&
      Number.isSafeInteger(task.savedPages) && task.savedPages >= 0 &&
      task.chapterPageCounts.length <= task.chapterIds.length &&
      task.chapterPageCounts.every((count: number) => Number.isSafeInteger(count) && count > 0);
  }

  /** Read-only validation first; no arbitrary files are deleted when repairing a checkpoint. */
  private static async reconcile(task: DownloadTask, generation: number): Promise<boolean> {
    const dir = DownloadQueue.folder(task.id);
    let saved = 0;
    const oldChapter = task.chapter;
    const oldPage = task.page;
    let rewind = false;
    for (let ch = 0; ch <= oldChapter && ch < task.chapterIds.length; ch++) {
      if (!DownloadQueue.live(task, generation)) {
        Log.audit(task.id, '检查点校验中止', '暂停/退后台后停止后续磁盘解码；不改已保存检查点');
        return false;
      }
      const expected = ch === oldChapter ? oldPage : task.chapterPageCounts[ch];
      if (expected === undefined) {
        task.chapter = ch; task.page = 0; rewind = true;
        Log.audit(task.id, '检查点回退', `章=${ch + 1}缺少原始页数；从本章重建，保留旧文件`);
        break;
      }
      const chapterDir = `${dir}/${String(ch + 1).padStart(4, '0')}`;
      if (fs.accessSync(chapterDir) && (fs.lstatSync(chapterDir).isSymbolicLink() || !fs.statSync(chapterDir).isDirectory())) {
        throw new Error('检查点章节目录不是普通目录');
      }
      const names = fs.accessSync(chapterDir) ? fs.listFileSync(chapterDir) : [];
      for (let page = 0; page < expected; page++) {
        if (!DownloadQueue.live(task, generation)) {
          Log.audit(task.id, '检查点校验中止', '仅当前页解码完成；不继续扫描后续页');
          return false;
        }
        const prefix = `${String(page + 1).padStart(6, '0')}.`;
        const candidates = names.filter((name: string) => name.startsWith(prefix) &&
          /[.](png|jpg|webp|gif|bmp)$/.test(name));
        if (candidates.length > 1) { throw new Error('检查点页有重复扩展名，拒绝猜测或删除用户文件'); }
        let valid = false;
        if (candidates.length === 1) {
          const path = `${chapterDir}/${candidates[0]}`;
          let decoder: image.ImageSource | undefined = undefined;
          let file: fs.File | undefined = undefined;
          try {
            if (fs.statSync(path).isFile()) {
              file = fs.openSync(path, fs.OpenMode.READ_ONLY);
              decoder = image.createImageSource(file.fd);
              const pixel = await decoder.createPixelMap();
              try {
                const info = await pixel.getImageInfo();
                valid = info.size.width > 0 && info.size.height > 0;
              } finally { await pixel.release(); }
            }
          } catch (error) {
            Log.audit(task.id, '检查点图片拒绝', `章=${ch + 1}页=${page + 1}不能读取/解码；不删除文件`);
          } finally { if (decoder !== undefined) { await decoder.release(); } if (file !== undefined) { fs.closeSync(file); } }
        }
        if (!DownloadQueue.live(task, generation)) { return false; }
        if (!valid) {
          task.chapter = ch; task.page = page; rewind = true;
          Log.audit(task.id, '检查点回退', `章=${ch + 1}页=${page + 1}缺失/无效；从该页重新下载，后续文件不删除`);
          break;
        }
        saved++;
      }
      if (rewind) { break; }
    }
    task.savedPages = saved;
    if (rewind) {
      task.chapterPageCounts = task.chapterPageCounts.slice(0, task.chapter + 1);
    }
    Log.audit(task.id, '检查点校验返回', `原章/页=${oldChapter}/${oldPage}；有效累计=${saved}；新章/页=${task.chapter}/${task.page}；回退=${rewind}`);
    DownloadQueue.persist();
    return rewind;
  }

  private static persist(): void {
    const path = DownloadQueue.ledger();
    const handle = fs.openSync(`${path}.tmp`, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
    try { fs.writeSync(handle.fd, JSON.stringify(DownloadQueue.tasks)); }
    finally { fs.closeSync(handle); }
    fs.renameSync(`${path}.tmp`, path);
  }

  static async add(sourceKey: string, comicId: string): Promise<DownloadTask> {
    const identity = JSON.stringify([sourceKey, comicId]);
    const pending = DownloadQueue.adding.get(identity);
    if (pending !== undefined) {
      Log.audit('downloads-add', '创建请求合并', '同一源/漫画已有创建请求，等待原任务，不重复创建目录');
      return pending;
    }
    const request = DownloadQueue.addUnqueued(sourceKey, comicId);
    DownloadQueue.adding.set(identity, request);
    try { return await request; }
    finally { DownloadQueue.adding.delete(identity); }
  }

  private static async addUnqueued(sourceKey: string, comicId: string): Promise<DownloadTask> {
    DownloadQueue.init();
    const existing = DownloadQueue.tasks.find((task: DownloadTask) =>
      task.sourceKey === sourceKey && task.comicId === comicId && task.status !== 'cancelled');
    if (existing !== undefined) { return existing; }
    const source = SourceManager.find(sourceKey);
    if (source?.loadComicInfo === undefined || source.loadComicPages === undefined) {
      throw new Error('源不支持下载章节');
    }
    const result = await source.loadComicInfo(comicId);
    if (result.error || result.dataOrNull === undefined) { throw new Error(result.errorMessage ?? '详情为空'); }
    const details = result.dataOrNull;
    const task = new DownloadTask();
    task.id = `DL_${Date.now()}_${Math.floor(Math.random() * 1000000000)}`;
    if (fs.accessSync(DownloadQueue.folder(task.id))) {
      throw new Error('下载目录标识冲突；未覆盖已有内容');
    }
    task.sourceKey = sourceKey;
    task.comicId = comicId;
    task.title = details.title;
    task.chapterIds = details.chapters !== undefined && details.chapters.length > 0 ? details.chapters.ids : [''];
    task.chapterTitles = details.chapters !== undefined && details.chapters.length > 0 ? details.chapters.titles : ['正文'];
    if (!DownloadQueue.validTask(task)) { throw new Error('章节信息无效，未创建下载目录'); }
    fs.mkdirSync(DownloadQueue.folder(task.id), true);
    const metadata = fs.openSync(`${DownloadQueue.folder(task.id)}/download.json`,
      fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
    try { fs.writeSync(metadata.fd, JSON.stringify({ owner: task.id, title: task.title, chapters: task.chapterTitles })); }
    finally { fs.closeSync(metadata); }
    DownloadQueue.tasks.push(task);
    DownloadQueue.persist();
    Log.audit(task.id, '下载创建', `章节数=${task.chapterIds.length}；默认暂停，等待用户开始`);
    return task;
  }

  static pause(id: string): void {
    const task = DownloadQueue.tasks.find((item: DownloadTask) => item.id === id);
    if (task === undefined) { return; }
    const active = task.status === 'running' || task.status === 'checking' || task.status === 'starting';
    if (!active && !task.queued) { return; }
    DownloadQueue.invalidate(id);
    task.queued = false;
    task.status = 'paused';
    DownloadQueue.persist();
    // Only the lease owner may release the shared native task; other parallel tasks must not.
    if (DownloadQueue.leaseOwner === id || BackgroundDownloadCoordinator.held(id)) {
      DownloadQueue.stopService(task).catch((_error: Object) => {});
    }
    Log.audit(id, '暂停请求', '租约立即失效；停止后台服务；晚到响应不得写盘，保留已验证检查点');
  }

  static async setForeground(value: boolean): Promise<void> {
    DownloadQueue.foreground = value;
    Log.audit('downloads-lifecycle', '应用前后台', `前台=${value}；恢复前台不自动开始下载`);
    if (!value) {
      for (const task of DownloadQueue.tasks) {
        if ((task.status === 'running' || task.status === 'checking' || task.status === 'starting') &&
          !BackgroundDownloadCoordinator.held(task.id)) {
          DownloadQueue.pause(task.id);
          task.error = `${BackgroundDownloadCoordinator.error || '后台数据传输尚未获系统许可'}；任务已暂停，回前台后请手动继续`;
          DownloadQueue.persist();
        }
      }
    }
  }

  static pauseAll(reason: string): void {
    const ids = DownloadQueue.tasks.filter((task: DownloadTask) => task.queued ||
      task.status === 'running' || task.status === 'checking' || task.status === 'starting').map((task: DownloadTask) => task.id);
    for (const id of ids) { DownloadQueue.pause(id); }
    Log.audit('downloads-lifecycle', '队列暂停', `原因=${reason}；暂停任务=${ids.length}；不初始化数据库/不删除文件`);
  }

  static async shutdown(reason: string): Promise<void> {
    DownloadQueue.foreground = false;
    DownloadQueue.pauseAll(reason);
    await DownloadQueue.stopService();
    for (const request of DownloadQueue.inflight.values()) { try { await request; } catch (_) {} }
  }

  static cancel(id: string): void {
    const task = DownloadQueue.tasks.find((item: DownloadTask) => item.id === id);
    if (task !== undefined) {
      DownloadQueue.invalidate(id);
      task.queued = false;
      task.status = 'cancelled';
      DownloadQueue.persist();
      if (DownloadQueue.leaseOwner === id || BackgroundDownloadCoordinator.held(id)) {
        DownloadQueue.stopService(task).catch((_error: Object) => {});
      }
      Log.audit(id, '取消请求', '租约失效并停止任务；不删除已下载内容');
    }
  }

  /** Explicit restart resets checkpoints, not files; verified replacement pages overwrite atomically. */
  static async restart(id: string): Promise<void> {
    if (!DownloadQueue.foreground) { throw new Error('请回到前台后手动重新开始'); }
    DownloadQueue.init();
    if (DownloadQueue.mutating.has(id)) { throw new Error('任务正在重置/删除'); }
    const task = DownloadQueue.tasks.find((item: DownloadTask) => item.id === id);
    if (task === undefined) { throw new Error('任务不存在'); }
    DownloadQueue.mutating.add(id);
    try {
      DownloadQueue.cancel(id);
      const request = DownloadQueue.inflight.get(id);
      if (request !== undefined) { try { await request; } catch (_) {} }
      DownloadQueue.ownedFolder(id);
      DownloadQueue.cleanParts(id);
      task.chapter = 0; task.page = 0; task.savedPages = 0;
      task.chapterPageCounts = []; task.currentChapterPages = 0;
      task.queued = false;
      task.status = 'paused'; task.error = '';
      DownloadQueue.persist();
      Log.audit(id, '从头重启', '等待旧代任务退出后归零；旧图片保留直到新图片验证通过后原子替换');
    } finally { DownloadQueue.mutating.delete(id); }
    await DownloadQueue.resume(id);
  }

  /** Caller must obtain explicit confirmation. Cancel + await the exact old runner before any unlink. */
  static async deleteTask(id: string): Promise<void> {
    DownloadQueue.init();
    if (DownloadQueue.mutating.has(id)) { throw new Error('任务正在重置/删除'); }
    const task = DownloadQueue.tasks.find((item: DownloadTask) => item.id === id);
    if (task === undefined) { throw new Error('任务不存在'); }
    DownloadQueue.mutating.add(id);
    try {
      // Validate before cancellation and again after the await (no computed arbitrary delete target).
      DownloadQueue.ownedFolder(id);
      DownloadQueue.cancel(id);
      const request = DownloadQueue.inflight.get(id);
      if (request !== undefined) { try { await request; } catch (_) {} }
      const dir = DownloadQueue.ownedFolder(id);
      DownloadQueue.validateTree(dir, dir);
      fs.rmdirSync(dir);
      DownloadQueue.tasks = DownloadQueue.tasks.filter((item: DownloadTask) => item !== task);
      DownloadQueue.persist();
      Log.audit(id, '下载删除', '只删除已验证所有权的DL任务文件夹/队列记录；不修改其他本地漫画或阅读历史');
    } finally { DownloadQueue.mutating.delete(id); }
  }

  static async resume(id: string): Promise<void> {
    DownloadQueue.init();
    if (DownloadQueue.mutating.has(id)) { throw new Error('任务正在重置/删除'); }
    if (DownloadQueue.inflight.get(id) !== undefined) { throw new Error('旧下载请求尚在退出，请稍后继续'); }
    const task = DownloadQueue.tasks.find((item: DownloadTask) => item.id === id);
    if (task === undefined || task.status === 'cancelled') { return; }
    if (!DownloadQueue.foreground) { throw new Error('应用在后台，请回前台手动继续'); }
    const generation = DownloadQueue.invalidate(id);
    const request = DownloadQueue.launch(task, generation);
    DownloadQueue.inflight.set(id, request);
    try { await request; }
    finally { if (DownloadQueue.inflight.get(id) === request) { DownloadQueue.inflight.delete(id); } }
  }

  /** Wait for a concurrency slot, then run. A pause/cancel while waiting exits without any network use. */
  private static async launch(task: DownloadTask, generation: number): Promise<void> {
    let admitted = false;
    try {
      admitted = await DownloadQueue.acquireSlot(task, generation);
      if (!admitted) {
        Log.audit(task.id, '下载未开始', '排队期间被暂停/取消；不发起网络请求、不改检查点');
        return;
      }
      if (!DownloadQueue.foreground) {
        task.status = 'paused';
        task.error = '应用在后台，请回前台手动继续';
        DownloadQueue.persist();
        return;
      }
      await DownloadQueue.run(task, generation);
    } finally {
      task.queued = false;
      if (admitted) { DownloadQueue.releaseSlot(task.id); }
    }
  }

  private static async acquireSlot(task: DownloadTask, generation: number): Promise<boolean> {
    if (DownloadQueue.running.size >= DownloadQueue.MAX_CONCURRENT_TASKS) {
      if (!DownloadQueue.queued(task, generation)) { return false; }
      task.queued = true;
      DownloadQueue.persist();
      Log.audit(task.id, '下载排队', `并行上限=${DownloadQueue.MAX_CONCURRENT_TASKS}；等待空位，不发起网络请求`);
      while (DownloadQueue.running.size >= DownloadQueue.MAX_CONCURRENT_TASKS) {
        await DownloadQueue.waitSlot();
        if (!DownloadQueue.queued(task, generation)) { task.queued = false; return false; }
      }
      task.queued = false;
      DownloadQueue.persist();
    }
    // No await between this check and the reservation: the cap can never be exceeded.
    DownloadQueue.running.set(task.id, generation);
    return true;
  }

  private static async run(task: DownloadTask, generation: number): Promise<void> {
    const id = task.id;
    const wasCompleted = task.status === 'completed';
    try {
      task.status = 'checking';
      if (!DownloadQueue.validTask(task)) { throw new Error('下载记录字段/检查点无效；保留原文件'); }
      const dir = DownloadQueue.ownedFolder(id);
      DownloadQueue.cleanParts(id);
      task.status = 'checking';
      task.error = '';
      const repaired = await DownloadQueue.reconcile(task, generation);
      if (!DownloadQueue.live(task, generation)) {
        Log.audit(id, '下载校验停止', `校验期间用户暂停/取消；状态=${task.status}；不启动网络`);
        return;
      }
      if (wasCompleted && !repaired) {
        task.status = 'completed'; DownloadQueue.persist();
        Log.audit(id, '下载校验完成', '所有已完成页都存在且可解码；未发起联网下载');
        return;
      }
      const source = SourceManager.find(task.sourceKey);
      if (source === undefined || source.loadComicPages === undefined) { throw new Error('下载源不可用'); }
      task.status = 'starting';
      DownloadQueue.persist();
      if (DownloadQueue.leaseAvailable(id)) {
        DownloadQueue.leaseOwner = id;
        try {
          await BackgroundDownloadCoordinator.start(id, (message: string): void => {
            if (DownloadQueue.generations.get(id) !== generation) { return; }
            DownloadQueue.pause(id);
            task.error = message;
            DownloadQueue.persist();
          });
        } catch (error) {
          // The background lease is an enhancement, not a precondition: while the
          // app is in the foreground the download must still run. Only pause when
          // there is no foreground execution to fall back on.
          if (DownloadQueue.leaseOwner === id) { DownloadQueue.leaseOwner = ''; }
          const message = error instanceof Error ? error.message : String(error);
          if (!DownloadQueue.foreground) {
            if (DownloadQueue.generations.get(id) === generation) {
              task.status = 'paused';
              task.error = message;
              DownloadQueue.persist();
            }
            throw new Error(message);
          }
          if (DownloadQueue.generations.get(id) === generation) { task.error = message; }
          Log.audit(id, '后台许可不可用', '继续前台下载；退到后台时该任务会暂停，可回前台手动继续');
        }
      } else {
        // One real native lease is shared by the whole queue: the other running tasks
        // keep downloading in the foreground instead of fighting over it.
        Log.audit(id, '后台租约让位', `并行任务=${DownloadQueue.leaseOwner}持有唯一后台数据传输租约；本任务仅前台下载`);
        if (!DownloadQueue.foreground) {
          task.status = 'paused';
          task.error = '并行任务已占用系统后台数据传输租约；请回前台后手动继续';
          DownloadQueue.persist();
          return;
        }
      }
      if (!DownloadQueue.live(task, generation)) { return; }
      task.status = 'running';
      // Keep the concrete background refusal visible during foreground fallback.
      if (BackgroundDownloadCoordinator.held(id)) { task.error = ''; }
      DownloadQueue.persist();
      while (task.chapter < task.chapterIds.length && DownloadQueue.live(task, generation)) {
        const ep = task.chapterIds[task.chapter];
        const result = await source.loadComicPages(task.comicId, ep);
        if (!DownloadQueue.live(task, generation)) { break; }
        if (result.error) { throw new Error(result.errorMessage ?? '章节请求失败'); }
        const urls = result.dataOrNull ?? [];
        if (urls.length === 0 || task.page > urls.length) { throw new Error('章节为空或检查点失效'); }
        task.currentChapterPages = urls.length;
        task.chapterPageCounts[task.chapter] = urls.length;
        DownloadQueue.persist();
        const chapterDir = `${dir}/${String(task.chapter + 1).padStart(4, '0')}`;
        if (!fs.accessSync(chapterDir)) { fs.mkdirSync(chapterDir, true); }
        while (task.page < urls.length && DownloadQueue.live(task, generation)) {
          const base = task.page;
          const end = Math.min(base + DownloadQueue.PAGE_WORKERS, urls.length);
          const outcomes: PageOutcome[] = [];
          for (let index = base; index < end; index++) { outcomes.push(new PageOutcome()); }
          const workers: Promise<void>[] = [];
          for (let index = base; index < end; index++) {
            workers.push(DownloadQueue.fetchPage(task, generation, source, urls, ep, chapterDir,
              index, outcomes[index - base]));
          }
          Log.audit(id, '并行取页', `章=${task.chapter + 1}；批次=${base + 1}-${end}/${urls.length}；并发=${end - base}`);
          // Every worker settles (never rejects), so no write is still in flight after this await.
          await Promise.all(workers);
          if (!DownloadQueue.live(task, generation)) {
            Log.audit(id, '并行批次中止', '批次返回时已暂停/取消/退后台；不推进检查点，晚到结果全部丢弃');
            break;
          }
          // Contiguous commit: only the verified prefix of the batch advances page/savedPages.
          for (let slot = 0; slot < outcomes.length; slot++) {
            const outcome = outcomes[slot];
            if (!outcome.saved) {
              throw new Error(outcome.error.length > 0 ? outcome.error : '页下载未完成；检查点停在已验证前缀');
            }
            task.page = base + slot + 1;
            task.savedPages++;
            DownloadQueue.persist();
            Log.audit(id, '下载检查点', `章=${task.chapter + 1}；页=${task.page}/${urls.length}；累计=${task.savedPages}；真实图片已验证`);
          }
        }
        if (task.page === urls.length && DownloadQueue.live(task, generation)) {
          task.chapter++;
          task.page = 0;
          DownloadQueue.persist();
        }
      }
      if (DownloadQueue.live(task, generation) && task.chapter === task.chapterIds.length) { task.status = 'completed'; }
      DownloadQueue.persist();
      Log.audit(id, '下载返回', `状态=${task.status}；已保存=${task.savedPages}`);
    } catch (error) {
      if (DownloadQueue.generations.get(id) !== generation) { return; }
      if (task.status !== 'cancelled' && task.status !== 'paused') {
        task.status = 'failed';
        task.error = error instanceof Error ? error.message : String(error);
      }
      DownloadQueue.persist();
      Log.audit(id, '下载异常', '任务检查点保留；可重试，不记录URL/凭据');
      if (task.status === 'paused' || task.status === 'cancelled') {
        Log.audit(id, '下载中止返回', `状态=${task.status}；有意中止，不将当前响应取消显示成失败`);
        return;
      }
      throw new Error(task.error || '下载暂停/取消时当前请求失败');
    } finally {
      // A retired runner must never release the shared lease of a newer run.
      if (DownloadQueue.leaseOwner === id) {
        DownloadQueue.leaseOwner = '';
        await DownloadQueue.stopService(task);
      }
    }
  }

  /** True when this run may negotiate the single native lease (no other running task owns it). */
  private static leaseAvailable(id: string): boolean {
    const owner = DownloadQueue.leaseOwner;
    if (owner.length === 0 || owner === id) { return true; }
    return !DownloadQueue.running.has(owner);
  }

  /**
   * One page of a parallel batch. Writes only this page index (unique inside the batch), keeps the
   * .part -> rename atomic semantics, and reports failure through the outcome instead of rejecting.
   */
  private static async fetchPage(task: DownloadTask, generation: number, source: ComicSource, urls: string[],
    episodeId: string, chapterDir: string, index: number, outcome: PageOutcome): Promise<void> {
    const id = task.id;
    try {
      if (!DownloadQueue.live(task, generation)) { return; }
      const config = await ImageRequests.resolve(source, urls[index], false, task.comicId, episodeId, id);
      if (!DownloadQueue.live(task, generation)) { return; }
      const bytes = await ImagePipeline.fetch(config, id,
        (): boolean => DownloadQueue.live(task, generation));
      // A pending response may finish after lock/hide; do not advance the checkpoint then.
      if (!DownloadQueue.live(task, generation)) {
        Log.audit(id, '晚到图片丢弃', `页=${index + 1}；暂停/取消/退后台后响应完成；不写新页、不推进检查点`);
        return;
      }
      if (bytes.byteLength < 64) { throw new Error('图片响应过短'); }
      const decoder = image.createImageSource(bytes);
      let extension = 'jpg';
      try {
        const info = await decoder.getImageInfo();
        if (info.size.width <= 0 || info.size.height <= 0) { throw new Error('图片无法解码'); }
        const decoded = await decoder.createPixelMap();
        await decoded.release();
        const mime = info.mimeType;
        extension = mime.includes('png') ? 'png' : mime.includes('webp') ? 'webp'
          : mime.includes('gif') ? 'gif' : mime.includes('bmp') ? 'bmp' : 'jpg';
      } finally { await decoder.release(); }
      if (!DownloadQueue.live(task, generation)) {
        Log.audit(id, '晚到解码丢弃', `页=${index + 1}；解码期间已暂停/后台；不写入新页`);
        return;
      }
      const stem = String(index + 1).padStart(6, '0');
      const name = `${stem}.${extension}`;
      const path = `${chapterDir}/${name}`;
      const otherVersions = fs.listFileSync(chapterDir).filter((entry: string) =>
        entry.startsWith(`${stem}.`) && /[.](png|jpg|webp|gif|bmp)$/.test(entry) && entry !== name);
      if (otherVersions.length > 0) { throw new Error('重下载图片格式与已有文件冲突；拒绝删除旧页或制造重复页'); }
      DownloadQueue.ownedFolder(id);
      if (fs.lstatSync(chapterDir).isSymbolicLink() || !fs.statSync(chapterDir).isDirectory()) {
        throw new Error('下载章节目录异常');
      }
      for (const target of [path, `${path}.part`]) {
        if (fs.accessSync(target) && (fs.lstatSync(target).isSymbolicLink() || !fs.statSync(target).isFile())) {
          throw new Error('下载页目标不是普通文件');
        }
      }
      try {
        const file = fs.openSync(`${path}.part`, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
        try {
          if (fs.writeSync(file.fd, bytes) !== bytes.byteLength) { throw new Error('下载图片写入不完整'); }
        } finally { fs.closeSync(file); }
        // No await between this lease check, rename, and checkpoint: one synchronous commit.
        if (!DownloadQueue.live(task, generation)) { return; }
        fs.renameSync(`${path}.part`, path);
      } finally {
        const partial = `${path}.part`;
        if (fs.accessSync(partial)) {
          DownloadQueue.ownedFolder(id);
          if (fs.lstatSync(chapterDir).isSymbolicLink() || fs.lstatSync(partial).isSymbolicLink() ||
            !fs.statSync(partial).isFile()) { throw new Error('拒绝清理异常下载临时页'); }
          fs.unlinkSync(partial);
        }
      }
      outcome.saved = true;
    } catch (error) {
      outcome.saved = false;
      outcome.error = error instanceof Error ? error.message : String(error);
    }
  }

  /** Diagnostics cleanup only; never deletes arbitrary completed downloads. */
  static cleanupProbe(id: string): void {
    const task = DownloadQueue.tasks.find((item: DownloadTask) => item.id === id);
    if (task === undefined || !/^HM_OFFLINE_READER_[0-9]+_[0-9]+$/.test(task.comicId) ||
        (task.sourceKey !== 'local' && !/^__HM_DOWNLOAD_LIFE_[0-9]+_[0-9]+$/.test(task.sourceKey)) ||
        task.status === 'running' || task.status === 'checking' || DownloadQueue.running.has(id)) {
      throw new Error('拒绝清理非离线验收任务或活动任务');
    }
    const dir = DownloadQueue.ownedFolder(id);
    DownloadQueue.validateTree(dir, dir);
    fs.rmdirSync(dir);
    DownloadQueue.tasks = DownloadQueue.tasks.filter((item: DownloadTask) => item.id !== id);
    DownloadQueue.persist();
    Log.audit(id, '验收下载清理', '只清理本地阅读样本对应的下载目录与任务，实际下载不变');
  }
}
