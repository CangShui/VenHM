import { router } from '@kit.ArkUI';
import { SettingsView } from '../features/SettingsView';
import { UiTheme, UiPageHeader } from '../components/UiKit';

/** Routed wrapper for the settings page (upstream keeps settings off the tab bar). */
@Entry
@Component
struct SettingsPage {
  build() {
    Column() {
      UiPageHeader({ title: '应用设置', subtitle: '阅读、内容与数据管理', onBack: () => {
        router.back();
      } })
      SettingsView().layoutWeight(1)
    }.width('100%').height('100%').backgroundColor(UiTheme.page)
  }
}
