import { router } from '@kit.ArkUI';
import { SearchView } from '../features/SearchView';
import { UiTheme, UiPageHeader } from '../components/UiKit';

/** Routed wrapper; source choice and search state remain in SearchView. */
@Entry
@Component
struct SearchPage {
  build() {
    Column() {
      UiPageHeader({ title: '搜索漫画', onBack: () => { router.back(); } })
      SearchView().layoutWeight(1)
    }.width('100%').height('100%').backgroundColor(UiTheme.page)
  }
}
