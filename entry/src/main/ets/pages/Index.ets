import { router } from '@kit.ArkUI';
import { HomeView } from '../features/HomeView';
import { BookshelfView } from '../features/BookshelfView';
import { ExploreView } from '../features/ExploreView';
import { CategoryView } from '../features/CategoryView';
import { AppInit } from '../foundation/AppInit';
import { AppContext } from '../foundation/AppContext';
import { Log } from '../foundation/Log';
import { VeneraUiDialog } from '../components/UiDialog';
import { UiBridge } from '../source/UiBridge';
import { UiTheme, UiIcon } from '../components/UiKit';

/** Presentation shell: original four tab identities and routes are unchanged. */
@Entry
@Component
struct Index {
  @State currentIndex: number = 0;
  private tabsController: TabsController = new TabsController();

  aboutToAppear(): void {
    // EntryAbility normally registers the context in onCreate(); the Previewer
    // does not run that lifecycle, so fall back to the UI host context.
    AppContext.ensureInitialized(this.getUIContext().getHostContext());
    // A @Builder needs its owning ViewPU. A standalone closure installed by
    // AppInit has no owner and crashes inside observeComponentCreation2.
    UiBridge.registerBuilder((): void => this.sourceDialog(), this.getUIContext());
    AppInit.init().catch((error: Object) => {
      Log.error('Index', `init failed: ${error}`);
    });
  }

  @Builder
  sourceDialog() {
    VeneraUiDialog()
  }

  private openPage(url: string): void {
    router.pushUrl({ url: url }).catch((error: Object) => {
      Log.error('Index', `cannot open ${url}: ${error}`);
    });
  }

  @Builder
  topBar() {
    Row({ space: 10 }) {
      Column({ space: 4 }) {
        Text(this.currentIndex === 1 ? '我的书架' : this.currentIndex === 2 ? '发现漫画' :
          this.currentIndex === 3 ? '漫画分类' : 'Venera')
          .fontSize(29).fontWeight(FontWeight.Bold).fontColor(UiTheme.ink).maxLines(1)
        Text(this.currentIndex === 1 ? '收藏与本地，随时接着读' : this.currentIndex === 2 ? '从喜欢的漫画源开始' :
          this.currentIndex === 3 ? '按类型和标签探索' : '今天，也读一点喜欢的')
          .fontSize(12).fontColor(UiTheme.muted).maxLines(1)
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      Button({ type: ButtonType.Circle }) { UiIcon({ name: 'history', iconSize: 21 }) }
        .width(44).height(44).backgroundColor(UiTheme.surface).accessibilityText('历史').id('action_history')
        .onClick(() => { this.openPage('pages/HistoryPage'); })
      Button({ type: ButtonType.Circle }) { UiIcon({ name: 'search', iconSize: 21 }) }
        .width(44).height(44).backgroundColor(UiTheme.surface).accessibilityText('搜索').id('action_search')
        .onClick(() => { this.openPage('pages/SearchPage'); })
    }.width('100%').padding({ left: 20, right: 20, top: 18, bottom: 20 })
  }

  @Builder
  tabBar(title: string, index: number) {
    Text(title).fontSize(12).fontColor(this.currentIndex === index ? UiTheme.accent : UiTheme.muted)
  }

  @Builder
  navigationItem(title: string, icon: string, index: number) {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 5 }) {
        UiIcon({ name: icon, iconSize: 24, color: this.currentIndex === index ? UiTheme.accent : '#535B69' })
        Text(title).fontSize(11).fontWeight(this.currentIndex === index ? FontWeight.Medium : FontWeight.Regular)
          .fontColor(this.currentIndex === index ? UiTheme.accent : UiTheme.secondary)
      }.width('100%').height(62).justifyContent(FlexAlign.Center)
    }.layoutWeight(1).height(62).borderRadius(24)
      .backgroundColor(this.currentIndex === index ? '#F1F7FF' : Color.Transparent)
      .accessibilityText(title).id(`tab_${index}`)
      .onClick(() => { this.currentIndex = index; this.tabsController.changeIndex(index); })
  }

  @Builder
  floatingNavigation() {
    Row({ space: 2 }) {
      this.navigationItem('首页', 'book', 0)
      this.navigationItem('书架', 'layers', 1)
      this.navigationItem('探索', 'globe', 2)
      this.navigationItem('分类', 'filter', 3)
      Button({ type: ButtonType.Normal }) {
        Column({ space: 5 }) {
          UiIcon({ name: 'settings', iconSize: 24, color: '#535B69' })
          Text('设置').fontSize(11).fontColor(UiTheme.secondary)
        }.width('100%').height(62).justifyContent(FlexAlign.Center)
      }.layoutWeight(1).height(62).borderRadius(24).backgroundColor(Color.Transparent)
        .accessibilityText('设置').id('action_settings')
        .onClick(() => { this.openPage('pages/SettingsPage'); })
    }.width('91%').constraintSize({ maxWidth: 440 }).padding(7).height(76)
      .backgroundColor(UiTheme.surface).borderRadius(32)
      .border({ width: 1, color: '#F0F2F6' })
      .shadow({ radius: 24, color: '#140F203A', offsetY: 8 }).margin({ bottom: 16 })
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        this.topBar()
        Tabs({ barPosition: BarPosition.End, controller: this.tabsController }) {
          TabContent() {
            HomeView({
              onOpenTab: (index: number) => {
                this.currentIndex = index;
                this.tabsController.changeIndex(index);
              }
            })
          }.tabBar(this.tabBar('首页', 0))
          TabContent() { BookshelfView() }.tabBar(this.tabBar('收藏', 1))
          TabContent() { ExploreView() }.tabBar(this.tabBar('探索', 2))
          TabContent() { CategoryView() }.tabBar(this.tabBar('分类', 3))
        }.barHeight(0).onChange((index: number) => { this.currentIndex = index; })
          .width('100%').layoutWeight(1)
      }.width('100%').height('100%')
      this.floatingNavigation()
    }.width('100%').height('100%').backgroundColor(UiTheme.page)
  }
}
