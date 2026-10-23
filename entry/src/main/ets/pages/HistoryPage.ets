import { promptAction, router } from '@kit.ArkUI';
import { AsyncComicImage, EmptyView, ErrorView, LoadingView } from '../components/ComicWidgets';
import { AppContext } from '../foundation/AppContext';
import { AppInit } from '../foundation/AppInit';
import { Log } from '../foundation/Log';
import { HistoryNavigation } from '../features/HistoryNavigation';
import { History, HistoryDao } from '../storage/HistoryDao';
import { UiTheme } from '../components/UiKit';
import { UiStyles } from '../components/UiModifiers';

/** Keep off-screen covers out of the component tree, including after select-all. */
class HistoryListSource implements IDataSource {
  private items: History[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): History {
    return this.items[index];
  }

  replace(items: History[]): void {
    this.items = items;
    this.notifyReload();
  }

  notifyReload(): void {
    for (const listener of this.listeners) {
      listener.onDataReloaded();
    }
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }
}

/**
 * Reading history, corresponding to features/history/history_page.dart.
 * Pagination has no total-record cap. Reading/refreshing never removes history;
 * every destructive operation is gated by an explicit confirmation dialog.
 */
@Entry
@Component
struct HistoryPage {
  @State items: History[] = [];
  @State loading: boolean = true;
  @State loadingMore: boolean = false;
  @State hasMore: boolean = false;
  @State error: string = '';
  @State pagingError: string = '';
  @State multiSelect: boolean = false;
  @State selectedKeys: string[] = [];
  @State selectingAll: boolean = false;
  @State confirming: boolean = false;
  @State deleting: boolean = false;
  @State navigationKey: string = '';
  private dataSource: HistoryListSource = new HistoryListSource();
  private pageSize: number = 100;
  private nextOffset: number = 0;
  private disposed: boolean = false;
  private visible: boolean = false;
  private refreshPending: boolean = false;
  private reading: boolean = false;
  private selectedSet: Set<string> = new Set<string>();
  private historyChanged: () => void = () => {
    if (this.disposed || !this.visible) {
      return;
    }
    // The reader may finish its final queued save after onPageShow has run.
    if (this.busy()) {
      this.refreshPending = true;
    } else {
      this.refresh();
    }
  };

  aboutToAppear(): void {
    this.disposed = false;
    AppContext.ensureInitialized(this.getUIContext().getHostContext());
    HistoryDao.addListener(this.historyChanged);
  }

  onPageShow(): void {
    this.visible = true;
    AppContext.ensureInitialized(this.getUIContext().getHostContext());
    // Load here, not in both lifecycle callbacks. Returning from the reader must
    // re-query saved progress and time, rather than retaining a stale card.
    if (this.reading || this.deleting || this.selectingAll || this.confirming || this.navigationKey.length > 0) {
      this.refreshPending = true;
      return;
    }
    this.refresh();
  }

  onPageHide(): void {
    this.visible = false;
  }

  aboutToDisappear(): void {
    this.disposed = true;
    this.visible = false;
    this.refreshPending = false;
    HistoryDao.removeListener(this.historyChanged);
  }

  onBackPress(): boolean {
    if (this.deleting || this.selectingAll) {
      return true;
    }
    if (this.multiSelect) {
      this.exitSelection();
      return true;
    }
    return false;
  }

  private busy(): boolean {
    return this.loading || this.loadingMore || this.selectingAll || this.confirming ||
      this.deleting || this.navigationKey.length > 0;
  }

  private refreshWhenReady(): void {
    if (this.refreshPending && this.visible && !this.disposed && !this.busy()) {
      this.refreshPending = false;
      this.refresh();
    }
  }

  private itemKey(item: History): string {
    // IDs can repeat between sources; database identity is (id, type).
    return `${item.type.value}:${item.id}`;
  }

  private isSelected(item: History): boolean {
    return this.selectedSet.has(this.itemKey(item));
  }

  private updateSelection(keys: string[]): void {
    this.selectedSet = new Set<string>(keys);
    this.selectedKeys = keys;
    this.dataSource.notifyReload();
  }

  private updateItems(items: History[]): void {
    this.items = items;
    this.dataSource.replace(items);
  }

  private async refresh(): Promise<void> {
    if (this.reading || this.deleting || this.selectingAll || this.confirming || this.navigationKey.length > 0) {
      return;
    }
    this.reading = true;
    this.loading = true;
    this.refreshPending = false;
    this.error = '';
    this.pagingError = '';
    try {
      await AppInit.init();
      const page = await HistoryDao.list(this.pageSize, 0);
      if (this.disposed) {
        return;
      }
      this.nextOffset = page.length;
      this.hasMore = page.length === this.pageSize;
      this.exitSelection();
      this.updateItems(page);
    } catch (error) {
      if (!this.disposed) {
        this.error = error instanceof Error ? error.message : String(error);
        Log.error('HistoryPage', `load failed: ${this.error}`);
      }
    } finally {
      this.reading = false;
      if (!this.disposed) {
        this.loading = false;
        this.refreshWhenReady();
      }
    }
  }

  /** Called only under the loading-more or select-all lock. */
  private async readNextPage(): Promise<void> {
    const page = await HistoryDao.list(this.pageSize, this.nextOffset);
    if (this.disposed) {
      return;
    }
    const merged: History[] = this.items.slice();
    const known = new Set<string>();
    for (const item of merged) {
      known.add(this.itemKey(item));
    }
    for (const item of page) {
      if (!known.has(this.itemKey(item))) {
        merged.push(item);
        known.add(this.itemKey(item));
      }
    }
    // Advance by the database page size, not the de-duplicated display size.
    this.nextOffset += page.length;
    this.hasMore = page.length === this.pageSize;
    this.updateItems(merged);
  }

  private async loadMore(): Promise<void> {
    if (this.busy() || !this.hasMore || this.error.length > 0) {
      return;
    }
    this.reading = true;
    this.loadingMore = true;
    this.pagingError = '';
    try {
      await this.readNextPage();
    } catch (error) {
      if (!this.disposed) {
        this.pagingError = error instanceof Error ? error.message : String(error);
        Log.error('HistoryPage', `next page failed: ${this.pagingError}`);
      }
    } finally {
      this.reading = false;
      if (!this.disposed) {
        this.loadingMore = false;
        this.refreshWhenReady();
      }
    }
  }

  private exitSelection(): void {
    this.multiSelect = false;
    this.updateSelection([]);
  }

  private toggleSelection(item: History): void {
    if (this.busy()) {
      return;
    }
    const key = this.itemKey(item);
    const keys = this.isSelected(item) ?
      this.selectedKeys.filter((value: string) => value !== key) : this.selectedKeys.concat([key]);
    this.updateSelection(keys);
  }

  private enterSelection(): void {
    if (!this.busy() && this.items.length > 0) {
      this.multiSelect = true;
      this.updateSelection([]);
    }
  }

  private deselectAll(): void {
    if (!this.busy()) {
      this.updateSelection([]);
    }
  }

  private async selectAcrossHistory(invert: boolean): Promise<void> {
    if (this.busy() || this.error.length > 0) {
      return;
    }
    this.selectingAll = true;
    this.reading = true;
    this.pagingError = '';
    try {
      // "All" means all saved history, not just the first loaded page.
      while (this.hasMore && !this.disposed) {
        await this.readNextPage();
      }
      if (this.disposed) {
        return;
      }
      const selected: string[] = [];
      for (const item of this.items) {
        if (!invert || !this.isSelected(item)) {
          selected.push(this.itemKey(item));
        }
      }
      this.updateSelection(selected);
    } catch (error) {
      if (!this.disposed) {
        this.pagingError = error instanceof Error ? error.message : String(error);
        promptAction.showToast({ message: '未能加载完整历史，未变更选择，请重试' });
      }
    } finally {
      this.reading = false;
      if (!this.disposed) {
        this.selectingAll = false;
        this.refreshWhenReady();
      }
    }
  }

  private async open(item: History, resume: boolean): Promise<void> {
    if (this.busy()) {
      return;
    }
    this.navigationKey = this.itemKey(item);
    try {
      if (resume) {
        await HistoryNavigation.resume(item);
      } else {
        await HistoryNavigation.openDetails(item);
      }
    } catch (error) {
      if (!this.disposed) {
        const message = error instanceof Error ? error.message : String(error);
        promptAction.showToast({ message: `${resume ? '继续阅读' : '打开详情'}失败：${message}`, duration: 4000 });
      }
    } finally {
      if (!this.disposed) {
        this.navigationKey = '';
        this.refreshWhenReady();
      }
    }
  }

  private async openOfflineCheck(): Promise<void> {
    if (this.busy()) {
      return;
    }
    this.navigationKey = 'offline-check';
    try {
      await router.pushUrl({ url: 'pages/UsabilityPage' });
    } catch (error) {
      if (!this.disposed) {
        const message = error instanceof Error ? error.message : String(error);
        promptAction.showToast({ message: `打开离线验收失败：${message}` });
      }
    } finally {
      if (!this.disposed) {
        this.navigationKey = '';
        this.refreshWhenReady();
      }
    }
  }

  private selectedItems(): History[] {
    return this.items.filter((item: History) => this.isSelected(item));
  }

  private async confirmDelete(items: History[], clearAll: boolean): Promise<void> {
    if (this.busy() || (!clearAll && items.length === 0)) {
      return;
    }
    // Snapshot the selected records before the dialog; selection changes cannot
    // silently expand what the user confirmed.
    const targets = items.slice();
    this.confirming = true;
    let confirmed: boolean = false;
    try {
      const result = await promptAction.showDialog({
        title: clearAll ? '清空阅读历史' : `删除 ${targets.length} 条历史`,
        message: clearAll ?
          '确定清空全部阅读历史？包括尚未加载的记录，删除后无法恢复。此操作不会删除漫画文件或收藏。' :
          `${targets.length === 1 ? `确定删除「${targets[0].title || '未命名漫画'}」的阅读历史？` :
            `确定删除选中的 ${targets.length} 条阅读历史？`}删除后无法恢复，不会删除漫画文件或收藏。`,
        buttons: [
          { text: '取消', color: '#666666' },
          { text: clearAll ? '清空全部' : '删除', color: '#D94838' }
        ]
      });
      confirmed = result.index === 1;
    } catch (error) {
      // Dialog dismissal is cancellation, never implicit confirmation.
      Log.info('HistoryPage', `delete confirmation dismissed: ${error}`);
    } finally {
      this.confirming = false;
    }
    if (!confirmed || this.disposed || !this.visible) {
      this.refreshWhenReady();
      return;
    }
    this.deleting = true;
    try {
      if (clearAll) {
        await HistoryDao.clear();
      } else if (targets.length === 1) {
        await HistoryDao.remove(targets[0].id, targets[0].type.value);
      } else {
        await HistoryDao.removeMany(targets);
      }
      if (!this.disposed) {
        this.exitSelection();
        promptAction.showToast({ message: clearAll ? '已清空阅读历史' : `已删除 ${targets.length} 条历史` });
      }
    } catch (error) {
      if (!this.disposed) {
        const message = error instanceof Error ? error.message : String(error);
        promptAction.showToast({ message: `删除失败：${message}`, duration: 4000 });
        Log.error('HistoryPage', `delete failed: ${message}`);
      }
    } finally {
      this.deleting = false;
      // Also re-query on failure instead of optimistically hiding saved rows.
      if (!this.disposed) {
        await this.refresh();
      }
    }
  }

  private displayTime(item: History): string {
    if (item.time <= 0) {
      return '阅读时间未知';
    }
    const date = new Date(item.time);
    const month = `${date.getMonth() + 1}`.padStart(2, '0');
    const day = `${date.getDate()}`.padStart(2, '0');
    const hour = `${date.getHours()}`.padStart(2, '0');
    const minute = `${date.getMinutes()}`.padStart(2, '0');
    return `${date.getFullYear()}-${month}-${day} ${hour}:${minute}`;
  }

  @Builder
  buildToolbar() {
    Column({ space: 14 }) {
      Text(this.multiSelect ? '取消' : '‹ 返回')
        .fontSize(14).fontColor(UiTheme.ink).height(44)
        .padding({ left: 16, right: 16 }).backgroundColor(UiTheme.surface).borderRadius(15)
        .enabled(!this.deleting && !this.selectingAll)
        .onClick(() => {
          if (this.multiSelect) {
            this.exitSelection();
          } else {
            router.back();
          }
        })
      Text(this.multiSelect ? `已选 ${this.selectedKeys.length} 条` : '阅读历史')
        .fontSize(30)
        .fontWeight(FontWeight.Bold).fontColor(UiTheme.ink)
        .width('100%')
        .maxLines(2)
      if (!this.multiSelect) {
        Flex({ wrap: FlexWrap.Wrap }) {
          Text('刷新')
            .fontSize(14)
            .fontColor(UiTheme.accent).height(44)
            .padding({ left: 16, right: 16 }).backgroundColor(UiTheme.accentSoft).borderRadius(15).margin({ right: 8, bottom: 8 })
            .enabled(!this.busy())
            .onClick(() => { this.refresh(); })
          Text('多选')
            .fontSize(14)
            .fontColor(UiTheme.ink).height(44)
            .padding({ left: 16, right: 16 }).backgroundColor('#EDF0F5').borderRadius(15).margin({ right: 8, bottom: 8 })
            .enabled(!this.busy() && this.items.length > 0)
            .onClick(() => { this.enterSelection(); })
        }.width('100%')
      }
    }
    .width('100%').alignItems(HorizontalAlign.Start)
    .padding({ left: UiTheme.gutter, right: UiTheme.gutter, top: 12, bottom: 12 })

    if (this.multiSelect) {
      Flex({ wrap: FlexWrap.Wrap }) {
        Button('全选').attributeModifier(UiStyles.secondary).margin({ right: 8, bottom: 8 })
          .onClick(() => { this.selectAcrossHistory(false); })
        Button('取消全选').attributeModifier(UiStyles.secondary).margin({ right: 8, bottom: 8 })
          .onClick(() => { this.deselectAll(); })
        Button('反选').attributeModifier(UiStyles.secondary).margin({ right: 8, bottom: 8 })
          .onClick(() => { this.selectAcrossHistory(true); })
        Button('删除').attributeModifier(UiStyles.danger).margin({ right: 8, bottom: 8 })
          .enabled(this.selectedKeys.length > 0)
          .onClick(() => { this.confirmDelete(this.selectedItems(), false); })
      }
      .enabled(!this.busy())
      .width('100%')
      .padding({ left: UiTheme.gutter, right: UiTheme.gutter, bottom: 10 })
    } else if (this.items.length > 0) {
      Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
        Text(this.hasMore ? `已加载 ${this.items.length} 条 · 最近阅读优先` : `共 ${this.items.length} 条 · 最近阅读优先`)
          .fontSize(12)
          .fontColor(UiTheme.secondary)
          .margin({ right: 12, bottom: 8 })
        Text('清空历史')
          .fontSize(13)
          .fontColor(UiTheme.danger).height(44)
          .padding({ left: 14, right: 14 }).backgroundColor(UiTheme.dangerSoft).borderRadius(15).margin({ bottom: 8 })
          .enabled(!this.busy())
          .onClick(() => { this.confirmDelete([], true); })
      }
      .width('100%')
      .padding({ left: UiTheme.gutter, right: UiTheme.gutter })
    }
  }

  @Builder
  historyCard(item: History) {
    Column({ space: 16 }) {
      // Detail/selection hit target and action buttons are siblings: resuming or
      // deleting must never bubble into the detail navigation handler.
      Row({ space: 14 }) {
        if (this.multiSelect) {
          Text(this.isSelected(item) ? '☑' : '☐')
            .fontSize(23)
            .fontColor(this.isSelected(item) ? UiTheme.accent : UiTheme.muted)
            .accessibilityText(this.isSelected(item) ? '已选择' : '未选择')
        }
        Column() {
          AsyncComicImage({
            url: item.cover,
            sourceKey: HistoryNavigation.sourceKey(item) ?? '',
            comicId: item.id,
            epId: item.epId ?? ''
          })
        }
        .width(72)
        .height(104)
        .borderRadius(14)
        .clip(true)
        Column({ space: 7 }) {
          Text(item.title || '未命名漫画')
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor(UiTheme.ink)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (item.subtitle.length > 0) {
            Text(item.subtitle).fontSize(12).maxLines(1)
              .fontColor(UiTheme.secondary)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          Text(HistoryNavigation.sourceName(item))
            .fontSize(11)
            .fontColor(UiTheme.accent)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(item.description()).fontSize(12).lineHeight(19).fontColor(UiTheme.secondary).maxLines(2)
          Text(this.displayTime(item)).fontSize(11).fontColor(UiTheme.muted)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
      .enabled(!this.busy())
      .onClick(() => {
        if (this.multiSelect) {
          this.toggleSelection(item);
        } else {
          this.open(item, false);
        }
      })

      if (!this.multiSelect) {
        Flex({ wrap: FlexWrap.Wrap }) {
          Text(this.navigationKey === this.itemKey(item) ? '正在打开…' : '点封面或标题查看详情')
            .fontSize(11)
            .fontColor(UiTheme.muted)
            .width('100%').margin({ bottom: 12 })
          Button('删除', { type: ButtonType.Normal })
            .attributeModifier(UiStyles.danger).margin({ right: 8, bottom: 8 })
            .onClick(() => { this.confirmDelete([item], false); })
          Button('继续阅读', { type: ButtonType.Normal })
            .attributeModifier(UiStyles.primary).margin({ right: 8, bottom: 8 })
            .onClick(() => { this.open(item, true); })
        }
        .width('100%')
        .enabled(!this.busy())
      }
    }
    .width('100%').alignItems(HorizontalAlign.Start)
    .padding(20)
    .borderRadius(UiTheme.cardRadius)
    .backgroundColor(UiTheme.surface)
    .border({ width: this.multiSelect && this.isSelected(item) ? 1 : 0, color: UiTheme.accent })
  }

  build() {
    Column() {
      this.buildToolbar()
      Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
        Text('无需联网，可验证阅读与历史保存')
          .fontSize(11).fontColor(UiTheme.secondary).margin({ right: 12, bottom: 8 })
        Button('离线验收', { type: ButtonType.Normal })
          .attributeModifier(UiStyles.secondary).margin({ bottom: 8 })
          .enabled(!this.busy())
          .onClick(() => {
            this.openOfflineCheck();
          })
      }
      .width('100%')
      .padding({ left: UiTheme.gutter, right: UiTheme.gutter, bottom: 10 })
      Divider().color(UiTheme.line)
      if (this.items.length === 0 && this.loading) {
        Column() { LoadingView({ message: '正在加载阅读历史…' }) }.layoutWeight(1)
      } else if (this.items.length === 0 && this.error.length > 0) {
        Column() {
          ErrorView({ message: `历史加载失败：${this.error}`, onRetry: () => { this.refresh(); } })
        }.layoutWeight(1)
      } else if (this.items.length === 0) {
        Column() { EmptyView({ message: '暂无阅读历史\n开始阅读后，你的进度会显示在这里' }) }.layoutWeight(1)
      } else {
        if (this.loading || this.selectingAll || this.deleting) {
          Row({ space: 8 }) {
            LoadingProgress().width(20).height(20)
            Text(this.deleting ? '正在删除…' : (this.selectingAll ?
              `正在加载全部历史，已加载 ${this.items.length} 条…` : '正在刷新历史…'))
              .fontSize(12).fontColor(UiTheme.secondary)
          }.width('100%').padding(10)
        }
        if (this.error.length > 0) {
          Row({ space: 8 }) {
            Text(`刷新失败，保留上次列表：${this.error}`)
              .fontSize(12).fontColor('#B73529').layoutWeight(1).maxLines(3)
            Button('重试').attributeModifier(UiStyles.secondary).enabled(!this.busy())
              .onClick(() => { this.refresh(); })
          }.width('100%').padding(12)
        }
        if (this.multiSelect) {
          Text(`已加载 ${this.items.length} 条${this.hasMore ? '，全选/反选会加载全部历史' : '，已显示全部历史'}`)
            .fontSize(12).fontColor(UiTheme.secondary).width('100%').padding(12)
        }
        List({ space: 10 }) {
          LazyForEach(this.dataSource, (item: History) => {
            ListItem() { this.historyCard(item) }
          }, (item: History) => `${this.itemKey(item)}:${item.time}:${this.multiSelect}:${this.isSelected(item)}`)
          ListItem() {
            Column({ space: 8 }) {
              if (this.loadingMore) {
                LoadingProgress().width(24).height(24)
                Text('正在加载更多…').fontSize(12).fontColor(UiTheme.secondary)
              } else if (this.pagingError.length > 0) {
                Text(`更多历史加载失败：${this.pagingError}`).fontSize(12).fontColor('#B73529').maxLines(3)
                Button('重试加载更多').attributeModifier(UiStyles.secondary).enabled(!this.busy())
                  .onClick(() => { this.loadMore(); })
              } else if (this.hasMore) {
                Button('加载更多历史').attributeModifier(UiStyles.secondary).enabled(!this.busy())
                  .onClick(() => { this.loadMore(); })
              } else {
                Text('已显示全部阅读历史').fontSize(12).fontColor(UiTheme.secondary)
              }
            }.width('100%').padding({ top: 20, bottom: UiTheme.bottomInset })
          }
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: UiTheme.gutter, right: UiTheme.gutter, top: 16 })
        .cachedCount(4)
        .onReachEnd(() => {
          if (this.pagingError.length === 0 && !this.multiSelect) {
            this.loadMore();
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(UiTheme.page)
  }
}
