import { router } from '@kit.ArkUI';
import { AppInit } from '../foundation/AppInit';
import { AppContext } from '../foundation/AppContext';
import { ReadingStats } from '../features/ReadingStats';
import { ReadingStatsDao, ReadingStatsRow, ReadingStatsSnapshot } from '../storage/ReadingStatsDao';
import { UiTheme, UiIcon, UiPageHeader } from '../components/UiKit';
import { UiStyles } from '../components/UiModifiers';

@Entry
@Component
struct StatisticsPage {
  @State data: ReadingStatsSnapshot = new ReadingStatsSnapshot();
  @State busy: boolean = true;
  @State error: string = '';
  @State tab: string = 'day';
  private disposed: boolean = false;
  aboutToAppear(): void { AppContext.ensureInitialized(this.getUIContext().getHostContext()); this.disposed = false; this.load(); }
  aboutToDisappear(): void { this.disposed = true; }
  private async load(): Promise<void> {
    this.busy = true; this.error = '';
    try { await AppInit.init(); const data = await ReadingStatsDao.snapshot(); if (!this.disposed) { this.data = data; } }
    catch (error) { if (!this.disposed) { this.error = '统计读取失败，请重试；历史记录未重置。'; } }
    finally { if (!this.disposed) { this.busy = false; } }
  }
  private today(): ReadingStatsRow {
    return this.data.days.find((item: ReadingStatsRow) => item.key === ReadingStats.day(Date.now())) ?? new ReadingStatsRow();
  }
  private rows(): ReadingStatsRow[] { return this.tab === 'day' ? this.data.days : this.tab === 'source' ? this.data.sources : this.data.comics; }
  @Builder
  summary(title: string, row: ReadingStatsRow) {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        Stack() { UiIcon({ name: 'chart', color: title === '今日' ? UiTheme.accent : '#8A68C7', iconSize: 23 }) }
          .width(46).height(46).borderRadius(15).backgroundColor(title === '今日' ? UiTheme.accentSoft : '#F0EAFA')
        Text(title).fontSize(16).fontWeight(FontWeight.Medium).fontColor(UiTheme.ink)
      }.width('100%')
      Text(ReadingStats.duration(row.durationMs)).fontSize(30).fontWeight(FontWeight.Bold).fontColor(UiTheme.ink).width('100%')
      Text(`${row.pages} 个不同图片页 · ${row.chapters} 个不同章节`).fontSize(13).lineHeight(20).fontColor(UiTheme.secondary).width('100%')
    }.padding(20).width('100%').backgroundColor(UiTheme.surface).borderRadius(UiTheme.cardRadius)
  }
  build() {
    Scroll() {
      Column() {
        UiPageHeader({ title: '阅读统计', subtitle: '仅记录本地阅读数据', onBack: () => { router.back(); } })
        Column({ space: 16 }) {
        Flex({ wrap: FlexWrap.Wrap }) {
          Button('刷新').attributeModifier(UiStyles.secondary).enabled(!this.busy).onClick(() => { this.load(); })
        }.width('100%')
        this.summary('今日', this.today())
        this.summary('累计', this.data.total)
        Text(`累计包含旧历史时长 ${ReadingStats.duration(this.data.undatedMs)}（无法分配日期）。新统计仅计前台已加载阅读区间，图片页/章节按源、漫画、稳定章节身份去重；不是翻页次数，旧记录不推算已读页数。`)
          .fontSize(12).lineHeight(20).fontColor(UiTheme.secondary).width('100%').padding(20)
          .backgroundColor(UiTheme.surface).borderRadius(UiTheme.cardRadius)
        Flex({ wrap: FlexWrap.Wrap }) {
          Button('按日期').attributeModifier(this.tab === 'day' ? UiStyles.quiet : UiStyles.secondary).height(44).margin({ right: 8, bottom: 8 }).onClick(() => { this.tab = 'day'; })
          Button('按来源').attributeModifier(this.tab === 'source' ? UiStyles.quiet : UiStyles.secondary).height(44).margin({ right: 8, bottom: 8 }).onClick(() => { this.tab = 'source'; })
          Button('按漫画').attributeModifier(this.tab === 'comic' ? UiStyles.quiet : UiStyles.secondary).height(44).margin({ right: 8, bottom: 8 }).onClick(() => { this.tab = 'comic'; })
        }.width('100%')
        if (this.error.length > 0) { Text(this.error).fontSize(13).lineHeight(20).fontColor(UiTheme.danger).width('100%') }
        if (this.busy) { Text('正在读取本地统计…').fontSize(13).fontColor(UiTheme.secondary).width('100%') }
        ForEach(this.rows(), (row: ReadingStatsRow) => {
          Column({ space: 8 }) {
            Text(this.tab === 'day' ? row.key : row.title || row.comicId || row.key).fontSize(17).fontWeight(FontWeight.Medium).fontColor(UiTheme.ink).width('100%')
            if (this.tab === 'comic') { Text(row.sourceKey).fontSize(12).fontColor(UiTheme.muted).width('100%') }
            Text(`${ReadingStats.duration(row.durationMs)} · ${row.pages} 页 · ${row.chapters} 章`).fontSize(13).lineHeight(20).fontColor(UiTheme.secondary).width('100%')
          }.padding(20).width('100%').backgroundColor(UiTheme.surface).borderRadius(UiTheme.cardRadius)
        }, (row: ReadingStatsRow) => `${this.tab}:${row.key}`)
      }.padding({ left: UiTheme.gutter, right: UiTheme.gutter, bottom: UiTheme.bottomInset })
        .width('100%').alignItems(HorizontalAlign.Start)
      }.width('100%').alignItems(HorizontalAlign.Start)
    }.width('100%').height('100%').scrollBar(BarState.Off).backgroundColor(UiTheme.page)
  }
}
