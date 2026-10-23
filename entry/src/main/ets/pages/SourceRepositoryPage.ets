import { router } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';
import { RepositoryParams } from '../model/RouteParams';
import { SourceCatalog, SourceCatalogEntry, SourceRepositories } from '../source/SourceRepository';
import { SourceInstaller, SourceInstallResult } from '../source/SourceInstaller';
import { AppContext } from '../foundation/AppContext';
import { AppInit } from '../foundation/AppInit';
import { ErrorView, LoadingView } from '../components/ComicWidgets';
import { Log } from '../foundation/Log';
import { UiTheme, UiIcon, UiPageHeader } from '../components/UiKit';
import { UiStyles } from '../components/UiModifiers';

/**
 * Repository browser.
 *
 * Dart original: lib/features/comic_source/source_repository_page.dart (735 lines).
 * The port loads the catalog, lists the entries and installs one at a time.
 * Batch install, update checks and version comparison are later modules.
 */
@Entry
@Component
struct SourceRepositoryPage {
  @State repositoryName: string = '';
  @State repositoryUrl: string = '';
  @State entries: SourceCatalogEntry[] = [];
  @State skippedCount: number = 0;
  @State installedKeys: string[] = [];
  @State installingKey: string = '';
  @State loading: boolean = true;
  @State error: string = '';

  aboutToAppear(): void {
    AppContext.ensureInitialized(this.getUIContext().getHostContext());
    const params = router.getParams() as RepositoryParams;
    if (params !== undefined && params !== null) {
      this.repositoryName = params.repositoryName ?? '';
      this.repositoryUrl = params.repositoryUrl ?? '';
    }
    this.load();
  }

  async load(): Promise<void> {
    this.loading = true;
    this.error = '';
    try {
      await AppInit.init();
      const catalog: SourceCatalog = await SourceRepositories.load(this.repositoryUrl);
      this.entries = catalog.entries;
      this.skippedCount = catalog.skipped.length;
      await this.refreshInstalled();
    } catch (error) {
      this.error = error instanceof Error ? error.message : String(error);
      Log.error('SourceRepositoryPage', this.error);
    } finally {
      this.loading = false;
    }
  }

  private async refreshInstalled(): Promise<void> {
    const installed = await SourceInstaller.listInstalled();
    const keys: string[] = [];
    for (let i = 0; i < installed.length; i++) {
      keys.push(installed[i].key);
    }
    this.installedKeys = keys;
  }

  private isInstalled(key: string): boolean {
    return this.installedKeys.indexOf(key) >= 0;
  }

  async install(entry: SourceCatalogEntry): Promise<void> {
    this.installingKey = entry.key;
    try {
      const result: SourceInstallResult = await SourceInstaller.install(entry);
      await this.refreshInstalled();
      promptAction.showToast({ message: result.message, duration: 4000 });
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      promptAction.showToast({ message: `安装失败: ${message}`, duration: 4000 });
      Log.error('SourceRepositoryPage', message);
    } finally {
      this.installingKey = '';
    }
  }

  build() {
    Column() {
      UiPageHeader({ title: this.repositoryName || '源仓库', subtitle: '浏览仓库中的漫画源', onBack: () => {
        router.back();
      } })
      Row() {
        Text('仓库列表').fontSize(13).fontColor(UiTheme.secondary).layoutWeight(1)
        Button('刷新').attributeModifier(UiStyles.quiet).onClick(() => {
          this.load();
        })
      }.width('100%').padding({ left: 24, right: 20, bottom: 12 })
      if (this.loading) {
        LoadingView({ message: '正在加载仓库列表…' }).layoutWeight(1)
      } else if (this.error.length > 0) {
        ErrorView({
          message: this.error,
          onRetry: () => {
            this.load();
          }
        }).layoutWeight(1)
      } else {
        List({ space: 12 }) {
          ListItem() {
            Column({ space: 8 }) {
              Text(`共 ${this.entries.length} 个源`).fontSize(16).fontWeight(FontWeight.Medium).fontColor(UiTheme.ink)
              if (this.skippedCount > 0) {
                Text(`已跳过 ${this.skippedCount} 个无效条目`).fontSize(12).fontColor('#D69A2D')
              }
              Text(this.repositoryUrl).fontSize(12).fontColor(UiTheme.muted).lineHeight(18).maxLines(2)
            }.alignItems(HorizontalAlign.Start).width('100%').padding(20)
              .backgroundColor(UiTheme.surface).borderRadius(UiTheme.cardRadius)
          }
          ForEach(this.entries, (entry: SourceCatalogEntry) => {
            ListItem() {
              Column({ space: 14 }) {
                Row({ space: 14 }) {
                  Stack() { UiIcon({ name: 'book', color: UiTheme.accent, iconSize: 23 }) }
                    .width(46).height(46).borderRadius(15).backgroundColor(UiTheme.accentSoft)
                  Column({ space: 5 }) {
                    Text(entry.name).fontSize(16).fontWeight(FontWeight.Medium).fontColor(UiTheme.ink)
                    Text(entry.key).fontSize(12).fontColor(UiTheme.muted)
                  }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                  Text(`v${entry.version}`).fontSize(12).fontColor(UiTheme.muted)
                }.width('100%').constraintSize({ minHeight: 48 })
                if (entry.description.length > 0) {
                  Text(entry.description).fontSize(13).fontColor(UiTheme.secondary).lineHeight(20).maxLines(2)
                }
                Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
                  if (this.isInstalled(entry.key)) {
                    Text('已安装').fontSize(13).fontColor(UiTheme.success).padding({ top: 12, bottom: 12 })
                  } else if (this.installingKey === entry.key) {
                    Text('安装中…').fontSize(13).fontColor('#D69A2D').padding({ top: 12, bottom: 12 })
                  } else {
                    Button('安装').attributeModifier(UiStyles.primary).onClick(() => {
                      this.install(entry);
                    })
                  }
                }.width('100%')
              }.alignItems(HorizontalAlign.Start).width('100%').padding(20)
                .backgroundColor(UiTheme.surface).borderRadius(UiTheme.cardRadius)
            }
          }, (entry: SourceCatalogEntry) => `${entry.key}@${entry.version}`)
        }.width('100%').layoutWeight(1).padding({ left: 20, right: 20, bottom: 24 }).scrollBar(BarState.Off)
      }
    }.width('100%').height('100%').backgroundColor(UiTheme.page)
  }
}
