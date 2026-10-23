import { router, promptAction } from '@kit.ArkUI';
import { AppInit } from '../foundation/AppInit';
import { FollowUpdate, FollowUpdatesDao } from '../storage/FollowUpdatesDao';
import { FollowUpdates } from '../features/FollowUpdates';
import { ComicDetailsParams } from '../model/RouteParams';
import { UiTheme, UiIcon, UiPageHeader } from '../components/UiKit';
import { UiStyles } from '../components/UiModifiers';

@Entry
@Component
struct FollowUpdatesPage {
  @State rows: FollowUpdate[] = [];
  @State checking: boolean = false;
  @State status: string = '';
  private generation: number = 0;
  private disposed: boolean = false;

  aboutToAppear(): void { this.disposed = false; this.load(); }
  onPageShow(): void { this.disposed = false; this.load(); }
  onPageHide(): void { this.disposed = true; this.generation++; this.checking = false; }
  aboutToDisappear(): void { this.onPageHide(); }

  private async load(): Promise<void> {
    try {
      await AppInit.init();
      const rows = await FollowUpdatesDao.list();
      if (!this.disposed) { this.rows = rows; }
    } catch (error) { if (!this.disposed) { this.status = '追更记录加载失败，请重试'; } }
  }

  private async check(): Promise<void> {
    if (this.checking) { return; }
    const token = ++this.generation;
    this.checking = true;
    this.status = '手动检查中（最多同时检查 2 本）；退出页面将停止排队';
    let completed = 0;
    try {
      await FollowUpdates.checkAll((row: FollowUpdate): void => {
        if (this.disposed || token !== this.generation) { return; }
        this.rows = this.rows.map((old: FollowUpdate) => old.sourceKey === row.sourceKey && old.comicId === row.comicId ? row : old);
        completed++;
        this.status = `已完成 ${completed} / ${this.rows.length}；各漫画结果如下`;
      }, (): boolean => !this.disposed && token === this.generation);
      if (!this.disposed && token === this.generation) { this.status = `检查完成：${completed} 本。首次成功检查仅建立基线。`; }
    } catch (error) { if (!this.disposed && token === this.generation) { this.status = '检查未完成，可能已有检查执行中或数据库异常；可稍后重试'; } }
    finally { if (!this.disposed && token === this.generation) { this.checking = false; } }
  }

  private open(row: FollowUpdate): void {
    const params: ComicDetailsParams = { sourceKey: row.sourceKey, comicId: row.comicId, title: row.title, cover: row.cover };
    router.pushUrl({ url: 'pages/ComicDetailsPage', params: params }).catch(() => { this.status = '打开原漫画失败'; });
  }

  private async mark(row: FollowUpdate): Promise<void> {
    try { await FollowUpdatesDao.markRead(row.sourceKey, row.comicId); await this.load(); }
    catch (error) { this.status = '标记已读失败，请重试'; }
  }

  private async remove(row: FollowUpdate): Promise<void> {
    try {
      const result = await promptAction.showDialog({ title: '取消追更', message: '仅移除此漫画的本地追更记录，不修改网络收藏或本地书架。',
        buttons: [{ text: '取消', color: '#666666' }, { text: '取消追更', color: '#D93025' }] });
      if (result.index !== 1) { return; }
      await FollowUpdatesDao.unfollow(row.sourceKey, row.comicId);
      await this.load();
    } catch (error) { this.status = '取消追更失败，请重试'; }
  }

  private summary(row: FollowUpdate): string {
    if (row.error.length > 0) { return `检查失败：${row.error}${row.unread ? '（仍有未读变化）' : ''}`; }
    if (row.checkedAt === 0) { return '尚未检查；首次成功检查建立基线'; }
    return `${row.unread ? '有未读章节/日期变化' : '没有未读变化'} · ${new Date(row.checkedAt).toLocaleString()}`;
  }

  build() {
    Scroll() {
      Column() {
        UiPageHeader({ title: '手动追更', subtitle: '更新由你主动检查', onBack: () => { router.back(); } })
        Column({ space: 16 }) {
        Column({ space: 14 }) {
          Row({ space: 12 }) {
            Stack() { UiIcon({ name: 'refresh', color: '#05AA7B', iconSize: 23 }) }
              .width(46).height(46).borderRadius(15).backgroundColor('#E5F7F0')
            Text('追更管理').fontSize(17).fontWeight(FontWeight.Medium).fontColor(UiTheme.ink)
          }.width('100%')
          Button(this.checking ? '检查中…' : '检查更新').attributeModifier(UiStyles.quiet).height(44).enabled(!this.checking).onClick(() => { this.check(); })
          Text('仅点击时读取漫画详情，不修改远端收藏；无后台定时任务。变化由章节与有效更新日期判断。').fontSize(12).lineHeight(20).fontColor(UiTheme.secondary).width('100%')
        }.padding(20).width('100%').alignItems(HorizontalAlign.Start).backgroundColor(UiTheme.surface).borderRadius(UiTheme.cardRadius)
        if (this.status.length > 0) { Text(this.status).fontSize(13).lineHeight(20).fontColor(UiTheme.secondary).width('100%').padding(16).backgroundColor(UiTheme.surface).borderRadius(16) }
        if (this.rows.length === 0) { Text('尚未追更。在漫画详情页点击「手动追更」即可加入。').fontSize(14).lineHeight(22).fontColor(UiTheme.secondary).padding(24).width('100%').backgroundColor(UiTheme.surface).borderRadius(UiTheme.cardRadius) }
        ForEach(this.rows, (row: FollowUpdate) => {
          Column({ space: 12 }) {
            Text(row.title).fontSize(18).fontWeight(FontWeight.Medium).fontColor(UiTheme.ink).width('100%').constraintSize({ minHeight: 44 }).onClick(() => { this.open(row); })
            Text(this.summary(row)).fontSize(13).lineHeight(21).fontColor(row.error.length > 0 ? UiTheme.danger : row.unread ? UiTheme.accent : UiTheme.secondary).width('100%')
            Flex({ wrap: FlexWrap.Wrap }) {
              Button('原漫画').attributeModifier(UiStyles.secondary).margin({ right: 8, bottom: 8 }).onClick(() => { this.open(row); })
              Button('标记已读').attributeModifier(UiStyles.quiet).height(44).margin({ right: 8, bottom: 8 }).enabled(row.current.length > 0 && !this.checking).onClick(() => { this.mark(row); })
              Button('取消追更').attributeModifier(UiStyles.danger).margin({ right: 8, bottom: 8 }).enabled(!this.checking).onClick(() => { this.remove(row); })
            }.width('100%')
          }.padding(20).width('100%').alignItems(HorizontalAlign.Start).backgroundColor(UiTheme.surface).borderRadius(UiTheme.cardRadius)
        }, (row: FollowUpdate) => JSON.stringify([row.sourceKey, row.comicId]))
        Button('刷新本地列表（不联网）').attributeModifier(UiStyles.secondary).enabled(!this.checking).onClick(() => { this.load(); })
      }.padding({ left: UiTheme.gutter, right: UiTheme.gutter, bottom: UiTheme.bottomInset }).width('100%').alignItems(HorizontalAlign.Start)
      }.width('100%').alignItems(HorizontalAlign.Start)
    }.width('100%').height('100%').scrollBar(BarState.Off).backgroundColor(UiTheme.page)
  }
}
