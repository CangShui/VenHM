import { router } from '@kit.ArkUI';
import { AppInit } from '../foundation/AppInit';
import { AppContext } from '../foundation/AppContext';
import { DownloadProgress, DownloadQueue, DownloadTask } from '../features/DownloadQueue';
import { Log } from '../foundation/Log';
import { UiTheme, UiIcon, UiPageHeader } from '../components/UiKit';
import { UiStyles } from '../components/UiModifiers';

@Entry
@Component
struct DownloadsPage {
  @State tasks: DownloadTask[] = [];
  /** Progress snapshots taken together with tasks in refresh(); never recomputed inside build(). */
  @State progresses: DownloadProgress[] = [];
  @State version: number = 0;
  @State error: string = '';
  private timer: number = -1;
  private disposed: boolean = false;
  private visible: boolean = true;

  private startRefresh(): void {
    if (this.disposed || !this.visible || this.timer >= 0) { return; }
    this.timer = setInterval(() => { this.refresh(); }, 500);
  }

  onPageShow(): void {
    this.visible = true;
    if (!this.disposed) { this.refresh(); this.startRefresh(); }
  }

  onPageHide(): void {
    this.visible = false;
    if (this.timer >= 0) { clearInterval(this.timer); this.timer = -1; }
    // A page is not the owner of the native DATA_TRANSFER service.
  }

  aboutToAppear(): void {
    this.disposed = false;
    AppContext.ensureInitialized(this.getUIContext().getHostContext());
    AppInit.init().then(() => {
      if (this.disposed) {
        Log.audit('downloads-page', '页面初始化取消', '初始化返回时页面已退出；不启动刷新计时器');
        return;
      }
      DownloadQueue.init();
      this.refresh();
      this.startRefresh();
    }).catch((error: Object) => { if (!this.disposed) { this.error = String(error); } });
  }

  aboutToDisappear(): void {
    this.disposed = true;
    this.visible = false;
    if (this.timer >= 0) { clearInterval(this.timer); this.timer = -1; }
    Log.audit('downloads-page', '页面退出', '只停止UI刷新；系统后台下载由队列租约管理，异步返回不再写页面状态');
  }

  private refresh(): void {
    const snapshot = DownloadQueue.tasks.slice();
    this.tasks = snapshot;
    this.progresses = snapshot.map((task: DownloadTask) => DownloadQueue.progress(task));
    this.version++;
  }

  private progressAt(index: number): DownloadProgress {
    return index < this.progresses.length ? this.progresses[index] : new DownloadProgress();
  }

  private chapterLabel(task: DownloadTask): string {
    const total = task.chapterIds.length;
    return `第 ${Math.min(task.chapter + 1, total)}/${total} 章`;
  }

  private async start(id: string): Promise<void> {
    try {
      this.error = '';
      await DownloadQueue.resume(id);
    } catch (error) { if (!this.disposed) { this.error = String(error); } }
    if (!this.disposed) { this.refresh(); }
  }

  /** Starts every paused/failed task; the queue admits at most MAX_CONCURRENT_TASKS at once. */
  private startAll(): void {
    this.error = '';
    for (const task of DownloadQueue.tasks) {
      if (task.status === 'paused' || task.status === 'failed') { this.start(task.id); }
    }
  }

  private confirmDelete(task: DownloadTask): void {
    this.getUIContext().showAlertDialog({
      title: '删除下载任务？',
      message: `将停止“${task.title}”，等待当前请求退出，再删除此任务自己的下载文件。不会删除其他本地漫画或阅读历史。`,
      primaryButton: { value: '保留', action: (): void => {} },
      secondaryButton: { value: '删除文件和任务', action: (): void => { this.remove(task.id); } }
    });
  }

  private confirmRestart(task: DownloadTask): void {
    this.getUIContext().showAlertDialog({
      title: '从头重新下载？',
      message: '等待旧请求退出后从第一章第一页开始。旧图片保留，只有新图片校验通过才原子替换；不会清空其他漫画。',
      primaryButton: { value: '取消', action: (): void => {} },
      secondaryButton: { value: '从头开始', action: (): void => { this.restart(task.id); } }
    });
  }

  private async remove(id: string): Promise<void> {
    try { this.error = ''; await DownloadQueue.deleteTask(id); }
    catch (error) { if (!this.disposed) { this.error = String(error); } }
    if (!this.disposed) { this.refresh(); }
  }

  private async restart(id: string): Promise<void> {
    try { this.error = ''; await DownloadQueue.restart(id); }
    catch (error) { if (!this.disposed) { this.error = String(error); } }
    if (!this.disposed) { this.refresh(); }
  }

  build() {
    Scroll() {
      Column() {
        UiPageHeader({ title: '下载任务', subtitle: '下载进度与队列管理', onBack: () => { router.back(); } })
        Column({ space: 16 }) {
        Column({ space: 12 }) {
          Row({ space: 12 }) {
            Stack() { UiIcon({ name: 'download', color: UiTheme.accent, iconSize: 23 }) }
              .width(46).height(46).backgroundColor(UiTheme.accentSoft).borderRadius(15)
            Text('下载说明').fontSize(17).fontWeight(FontWeight.Medium).fontColor(UiTheme.ink)
          }.width('100%')
          Text(`可同时下载 ${DownloadQueue.MAX_CONCURRENT_TASKS} 个任务，每个任务同时抓取 ${DownloadQueue.PAGE_WORKERS} 页；超出的任务排队等待空位。` +
            '手动开始后申请系统后台数据传输（持续通知），系统只接受一个后台租约，由其中一个任务持有，其余任务仅在前台下载。' +
            '系统拒绝/挂起时显示原因并暂停；进程重启只恢复暂停任务，不自动联网。完成后在收藏 → 本地中阅读。')
            .fontSize(12).lineHeight(20).fontColor(UiTheme.secondary).width('100%')
        }.alignItems(HorizontalAlign.Start).padding(20).width('100%')
          .backgroundColor(UiTheme.surface).borderRadius(UiTheme.cardRadius)
        if (this.error.length > 0) { Text(this.error).fontColor(UiTheme.danger).fontSize(13).lineHeight(20).padding(16).width('100%').backgroundColor(UiTheme.dangerSoft).borderRadius(16) }
        if (this.tasks.length === 0) { Text('尚无下载任务，请从漫画详情页加入').fontSize(14).fontColor(UiTheme.secondary).padding(24).width('100%').backgroundColor(UiTheme.surface).borderRadius(UiTheme.cardRadius) }
        Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
          Button('全部继续').attributeModifier(UiStyles.quiet).height(44).onClick(() => { this.startAll(); })
        }.width('100%')
        ForEach(this.tasks, (task: DownloadTask, index: number) => {
          Column({ space: 12 }) {
            Text(task.title).fontSize(18).fontWeight(FontWeight.Medium).fontColor(UiTheme.ink).width('100%')
            Progress({ value: this.progressAt(index).percent, total: 100, type: ProgressType.Linear })
              .color(UiTheme.accent).backgroundColor(UiTheme.line).width('100%')
            Text(`已保存 ${task.savedPages} 页 · ${this.chapterLabel(task)} · ${this.progressAt(index).percent}%`)
              .fontSize(13).fontColor(UiTheme.ink).width('100%')
            if (this.progressAt(index).indeterminate) {
              Text('总页数未知：百分比按已完成章节 + 本章进度估算，不虚构总页数').fontSize(12).lineHeight(19).fontColor(UiTheme.secondary)
            } else {
              Text(`共 ${this.progressAt(index).totalPages} 页（已知 ${this.progressAt(index).knownChapters}/${this.progressAt(index).totalChapters} 章页数）`)
                .fontSize(12).lineHeight(19).fontColor(UiTheme.secondary)
            }
            Text(`${task.status}${task.queued ? ' · 排队中（等待并行空位）' : ''}`)
              .fontSize(12).fontColor(UiTheme.accent).padding({ left: 10, right: 10, top: 6, bottom: 6 })
              .backgroundColor(UiTheme.accentSoft).borderRadius(10)
            Text(DownloadQueue.backgroundStatus(task.id)).fontSize(12).lineHeight(19).fontColor(UiTheme.secondary)
            if (task.error.length > 0) { Text(task.error).fontColor(UiTheme.danger).fontSize(12).lineHeight(19) }
            Flex({ wrap: FlexWrap.Wrap }) {
              if (task.status === 'running' || task.status === 'checking' || task.status === 'starting' || task.queued) {
                Button('暂停').attributeModifier(UiStyles.primary).margin({ right: 8, bottom: 8 }).onClick(() => { DownloadQueue.pause(task.id); this.refresh(); })
              } else if (task.status !== 'completed' && task.status !== 'cancelled') {
                Button('继续下载').attributeModifier(UiStyles.primary).margin({ right: 8, bottom: 8 }).onClick(() => { this.start(task.id); })
              } else if (task.status === 'completed') {
                Button('校验/修复下载').attributeModifier(UiStyles.quiet).height(44).margin({ right: 8, bottom: 8 }).onClick(() => { this.start(task.id); })
              }
              if (task.status !== 'completed' && task.status !== 'cancelled') {
                Button('取消任务').attributeModifier(UiStyles.secondary).margin({ right: 8, bottom: 8 }).onClick(() => { DownloadQueue.cancel(task.id); this.refresh(); })
              }
            }.width('100%')
            Divider().color(UiTheme.line)
            Flex({ wrap: FlexWrap.Wrap }) {
              Button('从头重启').attributeModifier(UiStyles.secondary).margin({ right: 8, bottom: 8 }).onClick(() => { this.confirmRestart(task); })
              Button('删除任务和文件').attributeModifier(UiStyles.danger).margin({ right: 8, bottom: 8 }).onClick(() => { this.confirmDelete(task); })
            }.width('100%')
          }.alignItems(HorizontalAlign.Start).padding(20).width('100%')
            .backgroundColor(UiTheme.surface).borderRadius(UiTheme.cardRadius)
        }, (task: DownloadTask) => `${task.id}-${this.version}`)
      }.width('100%').padding({ left: UiTheme.gutter, right: UiTheme.gutter, bottom: UiTheme.bottomInset })
        .alignItems(HorizontalAlign.Start)
      }.width('100%').alignItems(HorizontalAlign.Start)
    }.width('100%').height('100%').scrollBar(BarState.Off).backgroundColor(UiTheme.page)
  }
}
