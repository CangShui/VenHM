import { UiTheme } from './UiKit';
import { UiStyles } from './UiModifiers';
/**
 * Login dialog for comic sources.
 *
 * Dart original: lib/features/comic_source/comic_source_page.dart showed an
 * account section with a login form (and a WebView path for sites that need
 * one). This covers the account/password path, which is what most sources
 * declare via `account.login`.
 */
@CustomDialog
export struct LoginDialog {
  controller?: CustomDialogController;
  sourceName: string = '';
  account: string = '';
  password: string = '';
  onLogin?: (account: string, password: string) => void;

  build() {
    Column({ space: 12 }) {
      Text(`登录 ${this.sourceName}`)
        .fontSize(20)
        .fontWeight(FontWeight.Medium)

      TextInput({ placeholder: '账号 / 邮箱' })
        .height(48)
        .fontSize(14)
        .onChange((value: string) => {
          this.account = value;
        })

      TextInput({ placeholder: '密码' })
        .type(InputType.Password)
        .height(48)
        .fontSize(14)
        .onChange((value: string) => {
          this.password = value;
        })

      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.End }) {
        Button('取消').attributeModifier(UiStyles.secondary).margin({ left: 8, bottom: 8 })
          .layoutWeight(1)
          .backgroundColor('#F1F3F5')
          .fontColor('#333333')
          .onClick(() => {
            this.controller?.close();
          })
        Button('登录').attributeModifier(UiStyles.primary).margin({ left: 8, bottom: 8 })
          .layoutWeight(1)
          .onClick(() => {
            const handler = this.onLogin;
            if (handler !== undefined) {
              handler(this.account, this.password);
            }
            this.controller?.close();
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(24).backgroundColor(UiTheme.surface).borderRadius(24)
  }
}
