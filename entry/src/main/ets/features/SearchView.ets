import { UiTheme, UiIcon } from '../components/UiKit';
import { UiStyles } from '../components/UiModifiers';
import { router, promptAction } from '@kit.ArkUI';
import { Comic } from '../model/Comic';
import { CategoryComicsParams, ComicDetailsParams } from '../model/RouteParams';
import { ComicSource, SearchOptions } from '../source/ComicSource';
import { SourceManager } from '../source/SourceManager';
import { ComicCell, EmptyView, ErrorView, LoadingView } from '../components/ComicWidgets';
import { AppInit } from '../foundation/AppInit';
import { Log } from '../foundation/Log';
import { SearchSession } from './SearchSession';
import { SearchFilterPolicy } from './SearchFilterPolicy';
import { AggregatedSearchGroup, AggregatedSearchSession } from './AggregatedSearchSession';
import { AggregatedSearchList } from './AggregatedSearchList';
import { SelectedSource } from './SelectedSource';
import { SearchHistoryDao, SearchHistoryEntry } from '../storage/SearchHistoryDao';

/**
 * Source search.
 *
 * The source dropdown is the SAME selection as the explore and category tabs
 * (SelectedSource), so all three always serve the one source the user picked.
 * "聚合搜索" is an entry inside that dropdown, not a separate window.
 */
@Component
export struct SearchView {
  @State sourceOptions: string[] = [];
  @State selectedIndex: number = -1;
  @State selectedSourceKey: string = '';
  @State aggregated: boolean = false;
  @State keyword: string = '';
  @State results: Comic[] = [];
  @State loading: boolean = false;
  @State error: string = '';
  @State searched: boolean = false;
  @State loadingMore: boolean = false;
  @State ended: boolean = false;
  @State filterGroups: SearchOptions[] = [];
  @State filterValues: string[] = [];
  @State filterLoading: boolean = false;
  @State filterError: string = '';
  @State filtersExpanded: boolean = false;
  @State history: SearchHistoryEntry[] = [];
  @State groups: AggregatedSearchGroup[] = [];
  private readonly aggregateLabel: string = '聚合搜索（全部源）';
  private sourceKeys: string[] = [];
  private filtersSourceKey: string = '';
  private filterVersion: number = 0;
  private lifecycleVersion: number = 0;
  private subscription: number = 0;
  private queryVersion: number = 0;
  private aggregate: AggregatedSearchSession = new AggregatedSearchSession();
  private aggregateList: AggregatedSearchList = new AggregatedSearchList();
  private session: SearchSession = new SearchSession();
  private inputController: TextInputController = new TextInputController();
  private disposed: boolean = false;

  aboutToAppear(): void {
    this.disposed = false;
    SelectedSource.unsubscribe(this.subscription); this.subscription = 0;
    const version = ++this.lifecycleVersion;
    this.mirror();
    AppInit.init().then(() => {
      if (this.disposed || version !== this.lifecycleVersion) { return; }
      this.loadSources();
      this.reloadHistory();
      this.subscription = SelectedSource.subscribe((key: string) => {
        if (this.disposed || (!this.aggregated && key === this.selectedSourceKey)) { return; }
        // Same stable identity for search/explore/category, independent of each
        // view's capabilities and order; never pick a fallback behind the user.
        this.stopQueries();
        this.aggregated = false;
        this.selectedSourceKey = key;
        this.refreshSourceOptions();
        this.selectedIndex = this.indexOf(key);
        this.reloadFilters();
      });
    }).catch(() => {
      if (this.disposed || version !== this.lifecycleVersion) { return; }
      this.error = '初始化失败，请返回后重试';
    });
  }

  aboutToDisappear(): void {
    this.disposed = true; this.lifecycleVersion++; this.filterVersion++; this.queryVersion++;
    this.filterLoading = false;
    SelectedSource.unsubscribe(this.subscription); this.subscription = 0;
    this.session.invalidatePending();
    this.aggregate.cancel();
  }

  private mirror(): void {
    if (this.disposed || this.aggregated) { return; }
    this.results = this.session.results; this.loading = this.session.loading;
    this.loadingMore = this.session.loadingMore; this.searched = this.session.searched;
    this.error = this.session.error; this.ended = this.session.ended;
  }

  private indexOf(key: string): number {
    const at = this.sourceKeys.indexOf(key);
    return at < 0 ? -1 : at + 1;
  }

  private refreshSourceOptions(): void {
    const sources = SourceManager.all();
    this.sourceKeys = sources.map((source: ComicSource) => source.key);
    this.sourceOptions = [this.aggregateLabel].concat(sources.map((source: ComicSource) => source.name));
  }

  private loadSources(): void {
    if (this.disposed) { return; }
    this.refreshSourceOptions();
    const shared = SelectedSource.initialize();
    if (shared !== this.selectedSourceKey) { this.stopQueries(); this.aggregated = false; }
    this.selectedSourceKey = shared;
    this.selectedIndex = this.aggregated ? 0 : this.indexOf(shared);
    if (!this.aggregated && (this.filtersSourceKey !== shared || this.currentSource()?.search?.loadPage === undefined)) {
      this.reloadFilters();
    }
  }

  private stopQueries(): void {
    this.queryVersion++;
    this.session.cancel(); this.aggregate.cancel();
    this.results = []; this.groups = this.aggregateList.update([]); this.loading = false;
    this.loadingMore = false; this.searched = false; this.ended = false; this.error = '';
  }

  private currentSource(): ComicSource | undefined {
    return SourceManager.find(this.selectedSourceKey);
  }

  private selectSource(index: number): void {
    if (index < 0 || index >= this.sourceOptions.length) { return; }
    this.stopQueries(); this.filterVersion++; this.filterLoading = false;
    this.filtersExpanded = false;
    if (index === 0) {
      // Search mode only, not an invented source in the shared registry.
      this.aggregated = true; this.selectedIndex = 0; this.filterError = ''; return;
    }
    const key = this.sourceKeys[index - 1];
    this.aggregated = false; this.selectedSourceKey = key; this.selectedIndex = index;
    SelectedSource.select(key);
    // Also re-select the same real source after aggregation: no early return
    // may leave the dropdown on index0 or retain stale pending option metadata.
    this.reloadFilters();
  }

  private async reloadFilters(): Promise<void> {
    const version = ++this.filterVersion;
    const key = this.selectedSourceKey;
    this.filtersSourceKey = ''; this.filterLoading = true; this.filterError = '';
    this.filterGroups = []; this.filterValues = [];
    this.session.cancel(); this.mirror();
    try {
      const source = this.currentSource();
      if (source === undefined) { throw new Error('原先选择的源已移除；请选择其他源，不会自动换源'); }
      if (source.search?.loadPage === undefined) { throw new Error('所选源不支持搜索；当前选源仍与探索、分类保持一致'); }
      let groups: SearchOptions[] = source.search.searchOptions ?? [];
      if (source.search.optionsLoader !== undefined) {
        const result = await source.search.optionsLoader();
        if (this.disposed || version !== this.filterVersion || key !== this.selectedSourceKey) { return; }
        if (result.error || result.dataOrNull === undefined) { throw new Error('搜索筛选配置加载失败'); }
        groups = result.dataOrNull;
      }
      const values = SearchFilterPolicy.defaults(groups);
      if (this.disposed || version !== this.filterVersion || key !== this.selectedSourceKey) { return; }
      this.filterGroups = groups; this.filterValues = values; this.filtersSourceKey = key;
    } catch (error) {
      if (this.disposed || version !== this.filterVersion || key !== this.selectedSourceKey) { return; }
      const source = this.currentSource();
      this.filterError = source === undefined ? '原先选择的源已移除；请选择其他源，不会自动换源' :
        source.search?.loadPage === undefined ? '所选源不支持搜索；仍与探索、分类保持一致，可在任一处重新选择' :
          '搜索筛选配置无效或加载失败，请刷新；不会静默忽略筛选';
      Log.audit(`search-options-ui-${Date.now()}`, '筛选配置异常', '未回显源异常、关键词或参数；请对照源声明');
    } finally {
      if (!this.disposed && version === this.filterVersion && key === this.selectedSourceKey) { this.filterLoading = false; }
    }
  }

  private changeFilter(index: number, key: string): void {
    if (this.filterLoading || this.filtersSourceKey !== this.selectedSourceKey) { return; }
    try {
      this.filterValues = SearchFilterPolicy.change(this.filterGroups, this.filterValues, index, key);
      this.session.cancel(); this.mirror(); this.filterError = '';
    } catch (error) { this.filterError = '筛选项已变化，请刷新后重试'; }
  }

  private selectedFilter(group: SearchOptions, index: number, key: string): boolean {
    try { return SearchFilterPolicy.selected(group, this.filterValues[index] ?? '', key); }
    catch (error) { return false; }
  }

  private filterIndex(group: SearchOptions, index: number): number {
    return Array.from(group.options.keys()).indexOf(this.filterValues[index] ?? '');
  }

  async doSearch(): Promise<void> {
    try { this.inputController.stopEditing(); }
    catch (error) { Log.warn('SearchView', 'keyboard dismissal unavailable; continuing search'); }
    SearchHistoryDao.remember(this.keyword).then(() => { this.reloadHistory(); })
      .catch(() => { Log.warn('SearchView', 'search history write failed'); });
    if (this.aggregated) { await this.runAggregated(); return; }
    const source = this.currentSource();
    if (source?.search?.loadPage === undefined) { this.error = '没有可用的搜索源'; return; }
    if (this.filterLoading || this.filterError.length > 0 || this.filtersSourceKey !== source.key) {
      this.error = '请先等待筛选配置加载完成；失败时可刷新筛选'; return;
    }
    let options: string[];
    try { options = SearchFilterPolicy.validate(this.filterGroups, this.filterValues); }
    catch (error) { this.filterError = '筛选配置已变化，请刷新后重试'; return; }
    const pending = this.session.start(source, this.keyword, options);
    this.mirror();
    if (await pending) { this.mirror(); }
  }

  private async runAggregated(): Promise<void> {
    const version = ++this.queryVersion;
    const sources = SourceManager.searchable();
    this.error = ''; this.searched = true; this.groups = [];
    if (sources.length === 0) { this.error = '没有可搜索的源'; this.loading = false; return; }
    const keyword = this.keyword;
    await this.aggregate.start(sources, keyword, () => {
      if (!this.disposed && this.aggregated && version === this.queryVersion) {
        this.groups = this.aggregateList.update(this.aggregate.groups); this.loading = this.aggregate.running;
      }
    });
    if (!this.disposed && this.aggregated && version === this.queryVersion) {
      this.groups = this.aggregateList.update(this.aggregate.groups); this.loading = this.aggregate.running;
    }
  }

  private reloadHistory(): void {
    SearchHistoryDao.list().then((entries: SearchHistoryEntry[]) => {
      if (!this.disposed) { this.history = entries; }
    }).catch(() => { if (!this.disposed) { this.history = []; } });
  }

  private removeHistory(term: string): void {
    SearchHistoryDao.remove(term).then(() => { this.reloadHistory(); })
      .catch(() => { Log.warn('SearchView', 'search history delete failed'); });
  }

  private clearHistory(): void {
    SearchHistoryDao.clear().then(() => { this.reloadHistory(); })
      .catch(() => { Log.warn('SearchView', 'search history clear failed'); });
  }

  private async loadMore(): Promise<void> {
    const pending = this.session.more(); this.mirror();
    if (await pending) { this.mirror(); }
  }

  private openComic(comic: Comic): void {
    const key = comic.sourceKey.length > 0 ? comic.sourceKey : this.session.sourceKey;
    if (key.length === 0 || SourceManager.find(key) === undefined) { this.error = '该结果的漫画源已不可用，请重新搜索'; return; }
    const params: ComicDetailsParams = { sourceKey: key, comicId: comic.id, title: comic.title, cover: comic.cover };
    router.pushUrl({ url: 'pages/ComicDetailsPage', params: params }).catch(() => {
      promptAction.showToast({ message: '打开失败，请重试' });
    });
  }

  /** "更多" opens the full pager locked to that result's own source. */
  private moreOf(group: AggregatedSearchGroup): void {
    if (SourceManager.find(group.sourceKey) === undefined) { this.error = '原始源已移除，不会改用其他源'; return; }
    const params: CategoryComicsParams = { sourceKey: group.sourceKey, page: 'search',
      keyword: this.aggregate.keyword, label: `${group.sourceName} · 搜索` };
    router.pushUrl({ url: 'pages/CategoryComicsPage', params: params }).catch(() => { this.error = '无法打开该源完整结果，请重试'; });
  }

  @Builder
  filterGroup(group: SearchOptions, index: number) {
    Column({ space: 6 }) {
      Text(group.label || `筛选 ${index + 1}`).fontSize(13).fontWeight(FontWeight.Medium).width('100%')
      if (group.type === 'dropdown') {
        Select(Array.from(group.options.values()).map((label: string): SelectOption => {
          const option: SelectOption = { value: label }; return option;
        }))
          .selected(this.filterIndex(group, index))
          .value(group.options.get(this.filterValues[index] ?? '') ?? '请选择')
          .onSelect((selected: number) => {
            const keys = Array.from(group.options.keys());
            if (selected >= 0 && selected < keys.length) { this.changeFilter(index, keys[selected]); }
          })
      } else {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(Array.from(group.options.keys()), (key: string) => {
            Text(group.options.get(key) ?? key).fontSize(12)
              .fontColor(this.selectedFilter(group, index, key) ? '#FFFFFF' : '#333333')
              .backgroundColor(this.selectedFilter(group, index, key) ? '#0A59F7' : '#F1F3F5')
              .borderRadius(13).padding({ left: 14, right: 14, top: 12, bottom: 12 })
              .margin({ right: 6, bottom: 6 }).onClick(() => { this.changeFilter(index, key); })
          }, (key: string) => key)
        }.width('100%')
      }
    }.alignItems(HorizontalAlign.Start).width('100%').padding({ bottom: 10 })
  }

  @Builder
  aggregateGroup(group: AggregatedSearchGroup) {
    Column({ space: 8 }) {
      Row() {
        Text(group.sourceName).fontSize(15).fontWeight(FontWeight.Medium).layoutWeight(1)
        Button('更多').attributeModifier(UiStyles.quiet).onClick(() => { this.moreOf(group); })
      }.width('100%')
      if (group.status === 'loading' || group.status === 'queued') {
        Text(group.status === 'queued' ? '等待搜索…' : '搜索中…').fontSize(13).height(100)
      } else if (group.status === 'failed') {
        Text(group.error).fontSize(13).fontColor('#D93025')
        Button('重试此源').attributeModifier(UiStyles.secondary).onClick(() => { this.aggregate.retry(group.sourceKey); })
      } else if (group.status === 'empty' || group.status === 'cancelled') {
        Text(group.status === 'empty' ? '该源暂无结果' : '搜索已暂停；点击搜索重新执行').fontSize(13).height(70)
      } else {
        Scroll() {
          Row({ space: 10 }) {
            ForEach(group.results, (comic: Comic) => {
              Column() {
                ComicCell({ title: comic.title, subtitle: comic.subtitle, coverUrl: comic.cover,
                  sourceKey: comic.sourceKey, comicId: comic.id, onTapCell: () => { this.openComic(comic); } })
              }.width(112)
            }, (comic: Comic) => `${comic.sourceKey}@${comic.id}`)
          }
        }.scrollable(ScrollDirection.Horizontal).height(215).width('100%')
      }
    }.width('100%').padding(16).backgroundColor(UiTheme.surface).borderRadius(24).margin({ bottom: 12 })
  }

  build() {
    Column() {
      Column({ space: 12 }) {
        Row({ space: 10 }) {
          UiIcon({ name: 'globe', iconSize: 19, color: UiTheme.secondary })
          Select(this.sourceOptions.map((label: string): SelectOption => {
            const option: SelectOption = { value: label }; return option;
          }))
            .selected(this.selectedIndex)
            .value(this.selectedIndex >= 0 ? this.sourceOptions[this.selectedIndex] : '所选源不可用')
            .font({ size: 14 }).layoutWeight(1).height(48).backgroundColor(UiTheme.surface)
            .onSelect((index: number) => { this.selectSource(index); })
        }.width('100%').padding({ left: 14, right: 8 }).backgroundColor(UiTheme.surface).borderRadius(18)
        Row({ space: 10 }) {
        TextInput({ placeholder: '输入关键字', text: this.keyword, controller: this.inputController })
          .layoutWeight(1).height(48).fontSize(15).borderRadius(18).backgroundColor(UiTheme.surface).padding({ left: 18, right: 18 })
          .onChange((value: string) => {
            this.keyword = value;
            this.stopQueries();
          })
          .onSubmit(() => { this.doSearch(); })
        Button('搜索').attributeModifier(UiStyles.primary).width(80).height(48).enabled(this.aggregated || (!this.filterLoading && !this.loading))
          .onClick(() => { this.doSearch(); })
        }.width('100%')
      }.width('100%').padding({ left: 20, right: 20, bottom: 16 })
      if (this.aggregated) {
        Text('聚合搜索：同时查询全部可搜索源；每个源可单独重试，“更多”进入该源完整分页。')
          .fontSize(12).fontColor(UiTheme.secondary).padding({ left: 20, right: 20 })
      } else if (this.filterLoading) {
        LoadingView({ message: '正在读取源筛选…' }).height(48)
      } else if (this.filterError.length > 0) {
        Text(this.filterError).fontColor('#D93025').fontSize(12).padding(8)
        Button('刷新筛选').attributeModifier(UiStyles.secondary).onClick(() => { this.reloadFilters(); })
      } else if (this.filterGroups.length > 0) {
        Row({ space: 8 }) {
          Button(this.filtersExpanded ? '收起筛选' : `筛选（${this.filterGroups.length}）`).attributeModifier(UiStyles.quiet)
            .onClick(() => { this.filtersExpanded = !this.filtersExpanded; })
          Text('选择后点击搜索生效').fontSize(12).fontColor(UiTheme.muted).layoutWeight(1)
          Button('重置').fontSize(13).height(32).onClick(() => { this.reloadFilters(); })
        }.width('100%').padding({ left: 20, right: 20, bottom: 6 })
        if (this.filtersExpanded) {
          Scroll() {
            Column() {
              ForEach(this.filterGroups, (group: SearchOptions, index: number) => { this.filterGroup(group, index) },
                (group: SearchOptions, index: number) => `${this.selectedSourceKey}:${index}:${group.type}`)
            }.width('100%').padding({ left: 20, right: 20 })
          }.width('100%').height(220)
        }
      }
      if (this.aggregated) {
        if (this.loading && this.groups.length === 0) {
          LoadingView({ message: '聚合搜索中…' }).layoutWeight(1)
        } else if (!this.searched) {
          EmptyView({ message: '选择“聚合搜索”并输入关键字开始' }).layoutWeight(1)
        } else if (this.groups.length === 0) {
          EmptyView({ message: '没有可搜索的源' }).layoutWeight(1)
        } else {
          List() {
            LazyForEach(this.aggregateList, (group: AggregatedSearchGroup) => {
              ListItem() { this.aggregateGroup(group) }
            }, (group: AggregatedSearchGroup) => `${group.sourceKey}:${group.uiVersion}`)
          }.cachedCount(1).layoutWeight(1).width('100%').padding({ left: 20, right: 20, bottom: 24 }).scrollBar(BarState.Off)
        }
      } else if (this.loading) {
        LoadingView({ message: '搜索中…' }).layoutWeight(1)
      } else if (this.error.length > 0 && this.results.length === 0) {
        ErrorView({ message: this.error, onRetry: () => { this.doSearch(); } }).layoutWeight(1)
      } else if (!this.searched) {
        if (this.history.length > 0) {
          Row({ space: 8 }) {
            Text('搜索历史').fontSize(16).fontWeight(FontWeight.Bold).fontColor(UiTheme.ink).layoutWeight(1)
            Button('清空').attributeModifier(UiStyles.quiet).onClick(() => { this.clearHistory(); })
          }.width('100%').padding({ left: 20, right: 20, top: 6 })
          List() {
            ForEach(this.history, (entry: SearchHistoryEntry) => {
              ListItem() {
                Row({ space: 8 }) {
                  Text(entry.term).fontSize(14).fontColor(UiTheme.ink).layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  Button('删除').attributeModifier(UiStyles.danger).onClick(() => { this.removeHistory(entry.term); })
                }.width('100%').padding({ left: 16, right: 12, top: 8, bottom: 8 }).backgroundColor(UiTheme.surface)
              }
            }, (entry: SearchHistoryEntry) => entry.term)
          }.cachedCount(1).height(220).width('calc(100% - 40vp)').borderRadius(24).clip(true)
        }
        EmptyView({ message: '选择漫画源、筛选与关键字开始搜索' }).layoutWeight(1)
      } else if (this.results.length === 0) {
        EmptyView({ message: '没有找到结果' }).layoutWeight(1)
      } else {
        Grid() {
          ForEach(this.results, (item: Comic) => {
            GridItem() {
              ComicCell({ title: item.title, subtitle: item.subtitle, coverUrl: item.cover,
                sourceKey: item.sourceKey, comicId: item.id, onTapCell: () => { this.openComic(item); } })
            }
          }, (item: Comic) => `${item.sourceKey}@${item.id}`)
        }.columnsTemplate('1fr 1fr 1fr').columnsGap(10).rowsGap(14)
          .padding({ left: 20, right: 20, bottom: 12 }).width('100%').layoutWeight(1)
          .onReachEnd(() => { this.loadMore(); })
        if (this.error.length > 0) { Text(this.error).fontColor('#D93025').fontSize(12).padding(8) }
        Text(`已加载 ${this.results.length} 条`).fontSize(12).fontColor(UiTheme.muted).padding(4)
        Button(this.loadingMore ? '加载中…' : (this.ended ? '已到末页' : '加载更多')).attributeModifier(UiStyles.secondary).margin({ bottom: 16 })
          .enabled(!this.loadingMore && !this.ended).onClick(() => { this.loadMore(); })
      }
    }.width('100%').height('100%').backgroundColor(UiTheme.page)
  }
}
