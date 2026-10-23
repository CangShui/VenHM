import { router, promptAction } from '@kit.ArkUI';
import { AppInit } from '../foundation/AppInit';
import { AppContext } from '../foundation/AppContext';
import { Settings } from '../foundation/Settings';
import { DataSync } from '../features/DataSync';
import { UiTheme, UiIcon, UiPageHeader, UiSectionHeading } from '../components/UiKit';
import { UiStyles } from '../components/UiModifiers';

@Entry
@Component
struct SyncPage {
  @State endpoint: string = '';
  @State username: string = '';
  @State password: string = '';
  @State busy: boolean = false;
  @State result: string = '';

  aboutToAppear(): void {
    AppContext.ensureInitialized(this.getUIContext().getHostContext());
    AppInit.init().then(() => { this.endpoint = Settings.getString('webdavEndpoint', ''); })
      .catch((error: Object) => { this.result = String(error); });
  }

  aboutToDisappear(): void { this.password = ''; }

  private async sync(upload: boolean): Promise<void> {
    if (this.busy) { return; }
    this.busy = true;
    this.result = '';
    try {
      const choice = await promptAction.showDialog({
        title: upload ? '上传阅读数据备份' : '下载并合并阅读数据',
        message: upload ? '将收藏和历史发送到填写的WebDAV目录，并覆盖同名HM备份。不会上传账号或Cookie。'
          : '仅合并备份中不存在于本地的收藏/历史。已有本地记录不会被替换。不是完整双向冲突同步。',
        buttons: [{ text: '取消', color: '#777777' }, { text: '继续', color: '#0A59F7' }]
      });
      if (choice.index !== 1) { return; }
      DataSync.endpoint(this.endpoint);
      await Settings.setString('webdavEndpoint', this.endpoint);
      if (upload) {
        await DataSync.upload(this.endpoint, this.username, this.password);
        this.result = '上传成功（不含账号/Cookie）';
      } else {
        const count = await DataSync.downloadAndMerge(this.endpoint, this.username, this.password);
        this.result = `合并完成，处理${count}行；已有本地记录保留`;
      }
    } catch (error) { this.result = error instanceof Error ? error.message : String(error); }
    finally { this.busy = false; }
  }

  build() {
    Column() {
      UiPageHeader({ title: 'WebDAV 阅读数据备份', subtitle: '显式备份与保守合并', onBack: () => { router.back(); } })
      Scroll() {
        Column() {
          Column({ space: 12 }) {
            Row({ space: 12 }) {
              Stack() { UiIcon({ name: 'cloud', color: UiTheme.accent, iconSize: 24 }) }
                .width(46).height(46).borderRadius(15).backgroundColor(UiTheme.accentSoft)
              Text('仅备份阅读数据').fontSize(16).fontWeight(FontWeight.Medium).fontColor(UiTheme.ink)
            }.width('100%')
            Text('仅支持历史/收藏的显式备份与保守合并；不含账号、Cookie、漫画文件，不支持定时同步或双向冲突解决。')
              .fontSize(13).fontColor(UiTheme.secondary).lineHeight(21).width('100%')
          }.alignItems(HorizontalAlign.Start).width('100%').padding(20)
            .backgroundColor(UiTheme.surface).borderRadius(UiTheme.cardRadius)
          UiSectionHeading({ title: '连接信息' })
          Column({ space: 12 }) {
            Text('WebDAV 目录').fontSize(13).fontColor(UiTheme.secondary).width('100%')
            TextInput({ text: this.endpoint, placeholder: 'HTTPS WebDAV目录（须已存在）' })
              .height(50).fontSize(14).backgroundColor(UiTheme.page).borderRadius(14)
              .enabled(!this.busy).onChange((value: string) => { this.endpoint = value; })
            Text('用户名').fontSize(13).fontColor(UiTheme.secondary).width('100%').margin({ top: 4 })
            TextInput({ text: this.username, placeholder: 'WebDAV用户名（可留空）' })
              .height(50).fontSize(14).backgroundColor(UiTheme.page).borderRadius(14)
              .enabled(!this.busy).onChange((value: string) => { this.username = value; })
            Text('密码 / 应用密码').fontSize(13).fontColor(UiTheme.secondary).width('100%').margin({ top: 4 })
            TextInput({ text: this.password, placeholder: '仅本次会话，不保存' })
              .height(50).fontSize(14).backgroundColor(UiTheme.page).borderRadius(14)
              .type(InputType.Password).enabled(!this.busy).onChange((value: string) => { this.password = value; })
          }.width('100%').padding(20).backgroundColor(UiTheme.surface).borderRadius(UiTheme.cardRadius)
          Flex({ wrap: FlexWrap.Wrap }) {
            Button(this.busy ? '执行中…' : '上传备份').attributeModifier(UiStyles.primary)
              .enabled(!this.busy).margin({ right: 10, bottom: 10 }).onClick(() => { this.sync(true); })
            Button('下载并合并').attributeModifier(UiStyles.secondary)
              .enabled(!this.busy).margin({ bottom: 10 }).onClick(() => { this.sync(false); })
          }.width('100%').margin({ top: 20 })
          if (this.result.length > 0) {
            Text(this.result).fontSize(13).fontColor(UiTheme.secondary).lineHeight(21).width('100%').padding(20)
              .backgroundColor(UiTheme.surface).borderRadius(UiTheme.cardRadius)
          }
        }.width('100%').padding({ left: UiTheme.gutter, right: UiTheme.gutter, bottom: 32 })
      }.width('100%').layoutWeight(1).scrollBar(BarState.Off)
    }.width('100%').height('100%').backgroundColor(UiTheme.page)
  }
}
