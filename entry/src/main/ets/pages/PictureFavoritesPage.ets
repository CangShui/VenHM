import { router, promptAction } from '@kit.ArkUI';
import { AppInit } from '../foundation/AppInit';
import { PictureFavorite, PictureFavoritesDao } from '../storage/PictureFavoritesDao';
import { PictureFavorites } from '../features/PictureFavorites';
import { ComicDetailsParams, ReaderParams } from '../model/RouteParams';
import { UiTheme, UiIcon, UiPageHeader } from '../components/UiKit';
import { UiStyles } from '../components/UiModifiers';

@Entry
@Component
struct PictureFavoritesPage {
  @State rows: PictureFavorite[] = [];
  @State selected?: PictureFavorite = undefined;
  @State status: string = '';
  @State busy: boolean = false;
  private disposed: boolean = false;

  aboutToAppear(): void { this.disposed = false; this.load(); }
  onPageShow(): void { this.disposed = false; this.load(); }
  aboutToDisappear(): void { this.disposed = true; }

  private async load(): Promise<void> {
    try {
      await AppInit.init();
      const rows = await PictureFavoritesDao.list();
      if (!this.disposed) {
        this.rows = rows;
        if (this.selected !== undefined && !rows.some((row: PictureFavorite) => row.fileName === this.selected?.fileName)) { this.selected = undefined; }
      }
    } catch (error) { if (!this.disposed) { this.status = '图片收藏加载失败，请重试'; } }
  }

  private imagePath(row: PictureFavorite): string {
    try { return `file://${PictureFavorites.ownedPath(row.fileName)}`; }
    catch (error) { return ''; }
  }

  private openOriginal(row: PictureFavorite, read: boolean): void {
    if (read) {
      const params: ReaderParams = { sourceKey: row.sourceKey, comicId: row.comicId, title: row.title,
        epId: row.epId, page: row.page, origin: 'picture-favorites' };
      router.pushUrl({ url: 'pages/ReaderPage', params: params }).catch(() => { this.status = '打开原页失败'; });
    } else {
      const params: ComicDetailsParams = { sourceKey: row.sourceKey, comicId: row.comicId, title: row.title, cover: '' };
      router.pushUrl({ url: 'pages/ComicDetailsPage', params: params }).catch(() => { this.status = '打开原漫画失败'; });
    }
  }

  private async remove(row: PictureFavorite): Promise<void> {
    if (this.busy) { return; }
    this.busy = true;
    try {
      const result = await promptAction.showDialog({ title: '移除图片收藏',
        message: '将删除此应用图片收藏目录中的这一份图片副本及记录；不会删除原漫画、下载或缓存。此操作无法撤销。',
        buttons: [{ text: '取消', color: '#666666' }, { text: '删除副本', color: '#D93025' }] });
      if (result.index !== 1) { return; }
      await PictureFavorites.remove(row, true);
      if (this.selected?.fileName === row.fileName) { this.selected = undefined; }
      await this.load();
      this.status = '已移除图片收藏副本';
    } catch (error) { this.status = '移除失败；未删除非收藏目录的任何文件，可刷新后重试'; }
    finally { this.busy = false; }
  }

  build() {
    Scroll() {
      Column() {
        UiPageHeader({ title: '图片收藏', subtitle: '保存下来的阅读片刻', onBack: () => { if (this.selected !== undefined) { this.selected = undefined; } else { router.back(); } } })
        Column({ space: 16 }) {
        Button('刷新').attributeModifier(UiStyles.secondary).enabled(!this.busy).onClick(() => { this.load(); })
        if (this.status.length > 0) { Text(this.status).fontSize(13).lineHeight(20).fontColor(UiTheme.secondary).width('100%').padding(16).backgroundColor(UiTheme.surface).borderRadius(16) }
        if (this.selected !== undefined) {
          Column({ space: 16 }) {
            Image(this.imagePath(this.selected)).objectFit(ImageFit.Contain).width('100%').height(440).borderRadius(16)
              .onError(() => { this.status = '图片副本不存在或无法显示；可以返回原漫画或移除损坏记录'; })
            Text(`${this.selected.title} · 第 ${this.selected.page} 页`).fontSize(16).fontWeight(FontWeight.Medium).fontColor(UiTheme.ink).width('100%')
            Flex({ wrap: FlexWrap.Wrap }) {
              Button('原漫画').attributeModifier(UiStyles.secondary).margin({ right: 8, bottom: 8 }).onClick(() => { if (this.selected !== undefined) { this.openOriginal(this.selected, false); } })
              Button('回到原页').attributeModifier(UiStyles.quiet).height(44).margin({ right: 8, bottom: 8 }).onClick(() => { if (this.selected !== undefined) { this.openOriginal(this.selected, true); } })
              Button('移除').attributeModifier(UiStyles.danger).margin({ right: 8, bottom: 8 }).enabled(!this.busy).onClick(() => { if (this.selected !== undefined) { this.remove(this.selected); } })
            }.width('100%')
          }.padding(20).width('100%').alignItems(HorizontalAlign.Start).backgroundColor(UiTheme.surface).borderRadius(UiTheme.cardRadius)
        } else {
          Row({ space: 12 }) {
            Stack() { UiIcon({ name: 'image', color: '#C58A46', iconSize: 23 }) }
              .width(46).height(46).borderRadius(15).backgroundColor('#FCF1E3')
            Text('在阅读器通过明确的图片收藏操作保存当前页。这里仅显示已保存的处理后副本，不会自动抓取图片。')
              .fontSize(12).lineHeight(20).fontColor(UiTheme.secondary).layoutWeight(1)
          }.padding(20).width('100%').backgroundColor(UiTheme.surface).borderRadius(UiTheme.cardRadius)
          if (this.rows.length === 0) { Text('还没有图片收藏').fontSize(14).fontColor(UiTheme.secondary).padding(24).width('100%').backgroundColor(UiTheme.surface).borderRadius(UiTheme.cardRadius) }
          Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Start }) {
            ForEach(this.rows, (row: PictureFavorite) => {
              Column({ space: 10 }) {
                Image(this.imagePath(row)).objectFit(ImageFit.Contain).width('100%').height(170).borderRadius(14)
                  .onClick(() => { this.selected = row; })
                Text(`${row.title} · ${row.page} 页`).fontSize(13).fontColor(UiTheme.ink).width('100%').constraintSize({ minHeight: 44 }).maxLines(2).onClick(() => { this.selected = row; })
                Flex({ wrap: FlexWrap.Wrap }) {
                  Button('原漫画').attributeModifier(UiStyles.secondary).fontSize(12).height(44).margin({ right: 6, bottom: 8 }).onClick(() => { this.openOriginal(row, false); })
                  Button('移除').attributeModifier(UiStyles.danger).fontSize(12).height(44).margin({ right: 6, bottom: 8 }).enabled(!this.busy).onClick(() => { this.remove(row); })
                }.width('100%')
              }.padding(12).width('48%').margin({ right: '2%', bottom: 16 }).alignItems(HorizontalAlign.Start)
                .backgroundColor(UiTheme.surface).borderRadius(UiTheme.cardRadius)
            }, (row: PictureFavorite) => row.fileName)
          }.width('100%')
        }
      }.padding({ left: UiTheme.gutter, right: UiTheme.gutter, bottom: UiTheme.bottomInset }).width('100%').alignItems(HorizontalAlign.Start)
      }.width('100%').alignItems(HorizontalAlign.Start)
    }.width('100%').height('100%').scrollBar(BarState.Off).backgroundColor(UiTheme.page)
  }
}
