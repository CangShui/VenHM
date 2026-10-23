import { UiTheme, UiIcon } from '../components/UiKit';
import { UiStyles } from '../components/UiModifiers';
import { CategoryData, CategoryItem, CategoryPart, ComicSource } from '../source/ComicSource';
import { SourceManager } from '../source/SourceManager';
import { EmptyView, ErrorView, LoadingView } from '../components/ComicWidgets';
import { AppInit } from '../foundation/AppInit';
import { Log } from '../foundation/Log';
import { SelectedSource } from './SelectedSource';
import { TagRouting } from './TagRouting';
import { router } from '@kit.ArkUI';
import { RankingParams } from '../model/RouteParams';

/** Landing only: each entry preserves its exact target/param in a routed result page. */
@Component
export struct CategoryView {
  @State sourceNames: string[] = [];
  @State sourceIndex: number = -1;
  @State selectedSourceKey: string = '';
  @State category: CategoryData | undefined = undefined;
  @State loading: boolean = false;
  @State error: string = '';
  @State ready: boolean = false;
  private sourceKeys: string[] = [];
  private version: number = 0;
  private disposed: boolean = false;
  private subscription: number = 0;
  private initialized: boolean = false;

  aboutToAppear(): void {
    this.disposed = false;
    SelectedSource.unsubscribe(this.subscription);
    this.ready = false;
    const version = ++this.version;
    AppInit.init().then(() => {
      if (this.disposed || version !== this.version) { return; }
      this.selectedSourceKey = SelectedSource.initialize();
      this.ready = true; this.initialized = true;
      this.subscription = SelectedSource.subscribe((key: string) => {
        if (!this.disposed) { this.selectedSourceKey = key; this.reloadSources(); }
      });
      this.reloadSources();
    }).catch((error: Object) => {
      if (this.disposed || version !== this.version) { return; }
      this.ready = true; this.error = '初始化失败，请重试';
      Log.audit('category-init', '分类初始化异常', '不记录异常正文');
    });
  }

  aboutToDisappear(): void {
    this.disposed = true; this.version++; this.loading = false;
    SelectedSource.unsubscribe(this.subscription);
  }

  private reloadSources(): void {
    if (!this.initialized) { this.aboutToAppear(); return; }
    const sources = SourceManager.all();
    this.sourceKeys = sources.map((source: ComicSource) => source.key);
    this.sourceNames = sources.map((source: ComicSource) => source.name);
    this.sourceIndex = this.sourceKeys.indexOf(this.selectedSourceKey);
    this.loadCategories();
  }

  private async loadCategories(): Promise<void> {
    const version = ++this.version;
    const trace = `category-${Date.now()}-${version}`;
    // SYNC before any source callback (even absence, static data, throw or empty).
    this.loading = true; this.category = undefined; this.error = '';
    Log.audit(trace, '分类加载到达', '准备读取所选源；不按能力自动替换源');
    try {
      const source = SourceManager.find(this.selectedSourceKey);
      if (source === undefined) { throw new Error('选中的源已不可用，请选择其他源'); }
      if (source.categoryData === undefined && source.loadCategoryData === undefined) {
        throw new Error(`选中的源 ${source.name} 不支持分类`);
      }
      const category = source.categoryData ?? await source.loadCategoryData?.();
      if (this.disposed || version !== this.version) {
        Log.audit(trace, '分类结果拦截', '页面退出/源改变；丢弃旧结果'); return;
      }
      // E-Hentai deliberately declares parts:[] with enableRankingPage:true.
      if (category === undefined || (!category.enableRankingPage &&
        !category.parts.some((part: CategoryPart) => part.items.length > 0))) {
        throw new Error('该源返回空分类数据，请重试');
      }
      this.category = category;
      Log.audit(trace, '分类响应返回', `分组数=${category.parts.length}`);
    } catch (error) {
      if (this.disposed || version !== this.version) { return; }
      this.error = error instanceof Error ? error.message : '分类加载失败，请重试';
      Log.audit(trace, '分类加载异常', '缺少能力、空数据或回调失败；不记录服务器正文');
    } finally {
      if (!this.disposed && version === this.version) { this.loading = false; }
    }
  }

  private async openCategory(item: CategoryItem): Promise<void> {
    const trace = `category-open-${Date.now()}`;
    const key = this.selectedSourceKey;
    const version = this.version;
    try {
      if (this.disposed || this.loading || SourceManager.find(key) === undefined) { return; }
      await TagRouting.open(key, item, trace);
    } catch (error) {
      if (this.disposed || version !== this.version || key !== this.selectedSourceKey) { return; }
      this.error = error instanceof Error ? error.message : '分类跳转失败，请重试';
      Log.audit(trace, '分类跳转异常', '原目标不可用；未改用其他源');
    }
  }

  private openRanking(): void {
    const key = this.selectedSourceKey;
    const version = this.version;
    if (this.disposed || this.loading || !this.category?.enableRankingPage || SourceManager.find(key) === undefined) { return; }
    const params: RankingParams = { sourceKey: key };
    router.pushUrl({ url: 'pages/RankingPage', params: params }).catch(() => {
      if (!this.disposed && version === this.version && key === this.selectedSourceKey) { this.error = '排行榜跳转失败，请重试'; }
      Log.audit('category-ranking', '排行跳转异常', '未改用其他源；不记录异常正文');
    });
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        Select(this.sourceNames.map((label: string) => {
          const option: SelectOption = { value: label }; return option;
        }))
          .selected(this.sourceIndex)
          .value(this.sourceIndex >= 0 ? this.sourceNames[this.sourceIndex] : '所选源不可用')
          .font({ size: 14 }).height(48).borderRadius(18).backgroundColor(UiTheme.surface).layoutWeight(1)
          .onSelect((index: number) => {
            if (index >= 0 && index < this.sourceKeys.length) { SelectedSource.select(this.sourceKeys[index]); }
          })
        Button('刷新').attributeModifier(UiStyles.secondary).onClick(() => {
          if (!this.ready) { this.aboutToAppear(); } else { this.reloadSources(); }
        })
      }.width('100%').padding({ left: 20, right: 20, top: 4, bottom: 16 })
      if (!this.ready) {
        LoadingView({ message: '正在初始化…' }).layoutWeight(1)
      } else if (this.loading) {
        LoadingView({ message: '正在加载分类…' }).layoutWeight(1)
      } else if (this.error.length > 0) {
        ErrorView({ message: this.error, onRetry: () => { this.reloadSources(); } }).layoutWeight(1)
      } else if (this.sourceNames.length === 0) {
        EmptyView({ message: '没有已安装的源，请到源管理安装源' }).layoutWeight(1)
      } else {
        Scroll() {
          Column({ space: 8 }) {
            if (this.category?.enableRankingPage) {
              Button('排行榜').attributeModifier(UiStyles.quiet).width('100%').onClick(() => { this.openRanking(); })
                .margin({ top: 8, bottom: 8 })
            }
            ForEach(this.category?.parts ?? [], (part: CategoryPart) => {
              Column({ space: 8 }) {
                Text(part.title).fontSize(17).fontWeight(FontWeight.Bold).fontColor(UiTheme.ink).width('100%')
                Flex({ wrap: FlexWrap.Wrap }) {
                  ForEach(part.items, (item: CategoryItem) => {
                    Text(item.label).fontSize(13).fontColor('#333333').backgroundColor('#F1F3F5')
                      .borderRadius(14).padding({ left: 14, right: 14, top: 12, bottom: 12 })
                      .margin({ right: 8, bottom: 8 }).onClick(() => { this.openCategory(item); })
                  }, (item: CategoryItem, index: number) => `${index}:${item.page}:${item.label}`)
                }.width('100%')
              }.alignItems(HorizontalAlign.Start).width('100%').padding(18).backgroundColor(UiTheme.surface).borderRadius(24)
            }, (part: CategoryPart, index: number) => `${index}:${part.title}`)
          }.width('100%').padding({ left: 20, right: 20, bottom: 8 })
        }.layoutWeight(1).scrollBar(BarState.Off)
      }
    }.width('100%').height('100%').backgroundColor(UiTheme.page).padding({ bottom: UiTheme.bottomInset })
  }
}
