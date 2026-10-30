import { promptAction, router } from '@kit.ArkUI';
import { SourceManager } from '../source/SourceManager';
import { UiTheme, UiIcon } from './UiKit';
import { UiStyles } from './UiModifiers';

/** Details integration primitive: no implicit network mutation or image capture. */
@Component
export struct CollectionActionsPanel {
  @Prop sourceKey: string = '';
  @Prop comicId: string = '';
  @Prop title: string = '';
  @Prop cover: string = '';
  @Prop favId: string = '';
  /** Local favourite is the primary action; the detail page owns its folder UI. */
  @Prop localFavoriteLabel: string = '本地收藏';
  onLocalFavorite?: () => void;
  @State expanded: boolean = false;
  @State folders: string[] = [];
  @State folderNames: string[] = [];
  @State favorited: string[] = [];
  @State folderId: string = '';
  @State busy: boolean = false;
  @State status: string = '';

  private async openNetwork(): Promise<void> {
    if (this.busy) { return; }
    this.expanded = true;
    this.status = '';
    this.folders = [];
    this.folderNames = [];
    this.favorited = [];
    this.folderId = '';
    const source = SourceManager.find(this.sourceKey);
    if (source === undefined) { this.status = '原始漫画源不可用'; return; }
    if (!source.isLogged) { this.status = '请先登录此漫画源；不会回退到本地收藏'; return; }
    const data = source.favoriteData;
    if (data?.addOrDelFavorite === undefined) { this.status = '此漫画源未提供网络收藏增删能力'; return; }
    if (!data.multiFolder) { this.status = '请明确选择添加或移除远端收藏'; return; }
    if (data.loadFolders === undefined) { this.status = '源声明多收藏夹但没有 loadFolders'; return; }
    this.busy = true;
    try {
      const result = await data.loadFolders(this.comicId);
      if (result.error) { this.status = result.errorMessage ?? '远端收藏夹加载失败'; return; }
      this.folders = Array.from(result.data.keys());
      this.folderNames = Array.from(result.data.values());
      this.folderId = this.folders.length > 0 ? this.folders[0] : '';
      if (Array.isArray(result.subData)) { this.favorited = result.subData as string[]; }
      this.status = this.folders.length === 0 ? '远端没有可用的收藏夹，未执行增删' : '请选择远端收藏夹；只有点击并确认后才修改远端';
    } catch (error) { this.status = '远端收藏夹加载失败，请重试'; }
    finally { this.busy = false; }
  }

  private async mutate(adding: boolean): Promise<void> {
    if (this.busy) { return; }
    const source = SourceManager.find(this.sourceKey);
    const data = source?.favoriteData;
    if (source === undefined || !source.isLogged) { this.status = '请先登录此漫画源'; return; }
    if (data?.addOrDelFavorite === undefined || (data.multiFolder && !this.folders.includes(this.folderId))) {
      this.status = '远端收藏操作或收藏夹不可用'; return;
    }
    this.busy = true;
    try {
      const confirmation = await promptAction.showDialog({
        title: adding ? '添加到网络收藏' : '从网络收藏移除',
        message: `将修改「${source.name}」账号中的远端收藏，不影响本地收藏。是否继续？`,
        buttons: [{ text: '取消', color: '#666666' }, { text: '确认', color: '#0A59F7' }]
      });
      if (confirmation.index !== 1) { return; }
      if (!source.isLogged) { this.status = '账号已退出，请重新登录'; return; }
      const result = await data.addOrDelFavorite(this.comicId, this.folderId, adding, this.favId.length > 0 ? this.favId : undefined);
      if (result.error || result.dataOrNull !== true) { this.status = result.errorMessage ?? '远端未确认操作成功'; return; }
      this.status = adding ? '源接口已完成添加；可打开网络收藏刷新确认' : '源接口已完成移除；可打开网络收藏刷新确认';
      // Do not invent remote membership when sources only return void.
    } catch (error) { this.status = '网络收藏操作失败；请刷新远端状态后重试'; }
    finally { this.busy = false; }
  }

  build() {
    Column({ space: 14 }) {
      Row({ space: 12 }) {
        Stack() { UiIcon({ name: 'bookmark', color: '#8A68C7', iconSize: 22 }) }
          .width(44).height(44).borderRadius(15).backgroundColor('#F0EAFA')
        Text('收藏').fontSize(17).fontWeight(FontWeight.Medium).fontColor(UiTheme.ink)
      }.width('100%')
      Row({ space: 10 }) {
        Button(this.localFavoriteLabel).attributeModifier(UiStyles.primary)
          .height(44).layoutWeight(1).enabled(!this.busy)
          .onClick(() => { this.onLocalFavorite?.(); })
        Button('网络收藏').attributeModifier(UiStyles.secondary)
          .height(44).layoutWeight(1).enabled(!this.busy)
          .onClick(() => { this.openNetwork(); })
      }.width('100%')
      if (this.expanded) {
        Divider().color(UiTheme.line)
        if (this.folders.length > 0) {
          Select(this.folderNames.map((name: string): SelectOption => {
            const option: SelectOption = { value: name }; return option;
          }))
            .selected(this.folders.indexOf(this.folderId))
            .fontColor(UiTheme.ink).selectedOptionFontColor(UiTheme.accent).optionFontColor(UiTheme.ink).optionBgColor(UiTheme.surface).selectedOptionBgColor(UiTheme.accentSoft).menuBackgroundColor(UiTheme.surface).onSelect((index: number) => { this.folderId = this.folders[index]; })
            .enabled(!this.busy).height(44).font({ size: 14 }).fontColor(UiTheme.ink)
          Text(this.favorited.includes(this.folderId) ? '源报告：此漫画已在所选收藏夹' : '所选收藏夹未报告已收藏（以刷新远端为准）')
            .fontSize(12).lineHeight(20).fontColor(UiTheme.secondary).width('100%')
        }
        Flex({ wrap: FlexWrap.Wrap }) {
          Button('添加到远端').attributeModifier(UiStyles.quiet).height(44).margin({ right: 8, bottom: 8 }).enabled(!this.busy).onClick(() => { this.mutate(true); })
          Button('从远端移除').attributeModifier(UiStyles.danger).margin({ right: 8, bottom: 8 }).enabled(!this.busy).onClick(() => { this.mutate(false); })
          Button('登录').attributeModifier(UiStyles.secondary).margin({ right: 8, bottom: 8 }).onClick(() => {
            router.pushUrl({ url: 'pages/SourceAccountPage', params: { key: this.sourceKey } })
              .catch(() => { this.status = '打开账号失败'; });
          })
        }.width('100%')
        Button('浏览网络收藏').attributeModifier(UiStyles.secondary).onClick(() => {
          router.pushUrl({ url: 'pages/NetworkFavoritesPage', params: { sourceKey: this.sourceKey } })
            .catch(() => { this.status = '打开网络收藏失败'; });
        })
      }
      if (this.status.length > 0) { Text(this.status).fontSize(12).lineHeight(20).fontColor(UiTheme.secondary).width('100%') }
    }.width('100%').padding(20).alignItems(HorizontalAlign.Start)
      .backgroundColor(UiTheme.surface).borderRadius(UiTheme.cardRadius)
  }
}
