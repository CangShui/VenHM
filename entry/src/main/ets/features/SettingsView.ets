import { router } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';
import { AppInit } from '../foundation/AppInit';
import { AppContext } from '../foundation/AppContext';
import { JsRuntimeStatus } from '../source/JsRuntime';
import { SourceManager } from '../source/SourceManager';
import { UiTheme, UiIcon, UiSettingsRow, UiSectionHeading } from '../components/UiKit';

/**
 * Settings tab.
 *
 * Dart original: lib/features/settings/* (16 files, ~5.2k lines) - only the
 * entries the minimal loop needs are present. Every value goes through
 * Settings (preferences) so later modules can extend without a schema change.
 */
@Component
export struct SettingsView {
  @State sourceCount: number = 0;
  @State initError: string = '';

  aboutToAppear(): void {
    AppContext.ensureInitialized(this.getUIContext().getHostContext());
    AppInit.init()
      .then(() => {
        this.initError = '';
        this.sourceCount = SourceManager.all().length;
      })
      .catch((error: Object) => {
        // The Previewer does not show toasts reliably, so surface the failure
        // in the page itself - this is how a broken init becomes visible.
        this.initError = error instanceof Error ? error.message : String(error);
      });
  }

  build() {
    Scroll() {
      Column() {
        if (this.initError.length > 0) {
          Column({ space: 6 }) {
            Text('初始化失败（以下为真实错误信息）').fontSize(13).fontWeight(FontWeight.Medium).fontColor(UiTheme.danger)
            Text(this.initError).fontSize(12).fontColor(UiTheme.danger).lineHeight(18)
          }.alignItems(HorizontalAlign.Start).width('100%').padding(18)
            .backgroundColor(UiTheme.dangerSoft).borderRadius(UiTheme.cardRadius)
        }

        this.groupHeader('阅读与统计')
        Column() {
          UiSettingsRow({
            title: '阅读器设置', subtitle: '阅读模式、每屏图片与宽图拆分', icon: 'book', divider: true,
            onTap: () => {
              router.pushUrl({ url: 'pages/ReaderSettingsPage' }).catch((error: Object) => {
                promptAction.showToast({ message: '打开阅读设置失败，请稍后重试' });
              });
            }
          })
          UiSettingsRow({
            title: '阅读统计', subtitle: '查看阅读记录与阅读时长', icon: 'chart', tint: '#7A64CB', tone: '#F0EBFC',
            onTap: () => {
              router.pushUrl({ url: 'pages/StatisticsPage' }).catch(() => {
                promptAction.showToast({ message: '打开阅读统计失败，请稍后重试' });
              });
            }
          })
        }.width('100%').backgroundColor(UiTheme.surface).borderRadius(UiTheme.cardRadius).clip(true)

        this.groupHeader('内容与存储')
        Column() {
          UiSettingsRow({
            title: '缓存管理', subtitle: '查看占用、设置上限与清理缓存', icon: 'folder', tint: '#D69A2D', tone: '#FFF4DF', divider: true,
            onTap: () => {
              router.pushUrl({ url: 'pages/CacheSettingsPage' }).catch(() => {
                promptAction.showToast({ message: '打开缓存管理失败，请稍后重试' });
              });
            }
          })
          UiSettingsRow({
            title: '下载任务', subtitle: '管理已有漫画下载', icon: 'download', tint: '#05AA7B', tone: '#E5F7F1',
            onTap: () => {
              router.pushUrl({ url: 'pages/DownloadsPage' }).catch((error: Object) => {
                promptAction.showToast({ message: String(error) });
              });
            }
          })
        }.width('100%').backgroundColor(UiTheme.surface).borderRadius(UiTheme.cardRadius).clip(true)

        this.groupHeader('漫画源与收藏')
        Column() {
          UiSettingsRow({
            title: '源管理', subtitle: `已注册 ${this.sourceCount} 个源`, icon: 'globe', divider: true,
            onTap: () => {
              router.pushUrl({ url: 'pages/SourceManagerPage' })
                .catch((error: Object) => {
                  promptAction.showToast({ message: `打开失败: ${error}` });
                });
            }
          })
          UiSettingsRow({
            title: '网络收藏', subtitle: '查看漫画源中的收藏', icon: 'bookmark', tint: '#D9913D', tone: '#FFF2E4', divider: true,
            onTap: () => {
              router.pushUrl({ url: 'pages/NetworkFavoritesPage' }).catch(() => {
                promptAction.showToast({ message: '打开网络收藏失败，请稍后重试' });
              });
            }
          })
          UiSettingsRow({
            title: '图片收藏', subtitle: '收集喜欢的漫画画面', icon: 'image', tint: '#BA73B8', tone: '#F8ECF7', divider: true,
            onTap: () => {
              router.pushUrl({ url: 'pages/PictureFavoritesPage' }).catch(() => {
                promptAction.showToast({ message: '打开图片收藏失败，请稍后重试' });
              });
            }
          })
          UiSettingsRow({
            title: '追更', subtitle: '查看关注漫画的更新', icon: 'refresh', tint: '#05AA7B', tone: '#E5F7F1',
            onTap: () => {
              router.pushUrl({ url: 'pages/FollowUpdatesPage' }).catch(() => {
                promptAction.showToast({ message: '打开追更失败，请稍后重试' });
              });
            }
          })
        }.width('100%').backgroundColor(UiTheme.surface).borderRadius(UiTheme.cardRadius).clip(true)

        this.groupHeader('数据与备份')
        Column() {
          UiSettingsRow({
            title: 'WebDAV 阅读数据备份', subtitle: '备份收藏与历史，或下载并合并', icon: 'cloud', tint: '#6487CF', tone: '#EDF2FF',
            onTap: () => {
              router.pushUrl({ url: 'pages/SyncPage' }).catch((error: Object) => {
                promptAction.showToast({ message: String(error) });
              });
            }
          })
        }.width('100%').backgroundColor(UiTheme.surface).borderRadius(UiTheme.cardRadius).clip(true)

        this.groupHeader('关于与运行时')
        Column() {
          Row({ space: 16 }) {
            Stack() { UiIcon({ name: 'layers', color: '#7A64CB', iconSize: 23 }) }
              .width(46).height(46).borderRadius(15).backgroundColor('#F0EBFC')
            Column({ space: 5 }) {
              Text('QuickJS 漫画源脚本').fontSize(16).fontWeight(FontWeight.Medium).fontColor(UiTheme.ink)
              Text(JsRuntimeStatus.isAvailable ? '可以加载 .js 漫画源' : JsRuntimeStatus.unavailableReason)
                .fontSize(12).fontColor(UiTheme.muted).lineHeight(18)
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            Text(JsRuntimeStatus.isAvailable ? '可用' : '未接入').fontSize(12)
              .fontColor(JsRuntimeStatus.isAvailable ? UiTheme.success : '#D69A2D')
          }.width('100%').constraintSize({ minHeight: 82 }).padding(18)
          Divider().color(UiTheme.line).margin({ left: 80, right: 18 })
          Row({ space: 16 }) {
            Stack() { UiIcon({ name: 'info', color: '#6487CF', iconSize: 23 }) }
              .width(46).height(46).borderRadius(15).backgroundColor('#EDF2FF')
            Column({ space: 5 }) {
              Text('VenHM').fontSize(16).fontWeight(FontWeight.Medium).fontColor(UiTheme.ink)
              Text('VeneraNext 的原生鸿蒙（ArkTS/ArkUI）移植').fontSize(12).fontColor(UiTheme.muted).lineHeight(18)
              Text('bundle: com.venerahm.reader').fontSize(11).fontColor(UiTheme.muted)
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          }.width('100%').padding(18)
        }.width('100%').backgroundColor(UiTheme.surface).borderRadius(UiTheme.cardRadius)
      }.width('100%').padding({ left: UiTheme.gutter, right: UiTheme.gutter, bottom: UiTheme.bottomInset })
    }.width('100%').height('100%').backgroundColor(UiTheme.page).scrollBar(BarState.Off)
  }

  @Builder
  groupHeader(title: string) {
    UiSectionHeading({ title: title })
  }
}
