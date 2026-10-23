'use strict';
// Precisely scoped presentation edits; the independent guard verifies business
// methods and backend files after every pass. Never run this script twice.
const fs=require('node:fs'),path=require('node:path');const root=path.resolve(__dirname,'..');
function change(file,edit){const p=path.join(root,file),text=fs.readFileSync(p,'utf8');if(text.includes("from '../components/UiModifiers'"))throw Error('Already styled: '+file);const next=edit(text);fs.writeFileSync(p,next)}
function imports(text){return "import { UiTheme, UiIcon } from '../components/UiKit';\nimport { UiStyles } from '../components/UiModifiers';\n"+text}
function splitUI(text){const at=text.indexOf('  @Builder');if(at<0)throw Error('builder boundary missing');return [text.slice(0,at),text.slice(at)]}
change('entry/src/main/ets/features/HomeView.ets',text=>{
 const [prefix,original]=splitUI(text);let ui=original;
 ui=ui.replace("Text(title).fontSize(16).fontWeight(FontWeight.Medium)","Text(title).fontSize(18).fontWeight(FontWeight.Bold).fontColor(UiTheme.ink)");
 ui=ui.replace(".fontSize(13)\n          .fontColor('#0A59F7')",".fontSize(12).height(40)\n          .fontColor(UiTheme.accent)");
 ui=ui.replaceAll('left: 16, right: 16','left: 20, right: 20').replace('top: 16, bottom: 8','top: 26, bottom: 16');
 ui=ui.replaceAll('.width(92)','.width(108)').replaceAll('.height(124)','.height(148)').replaceAll('.borderRadius(8)','.borderRadius(16)');
 const begin=ui.indexOf('  @Builder\n  comicGrid('),end=ui.indexOf('\n  build()',begin);
 if(begin<0||end<0)throw Error('Home grid anchors missing');
 ui=ui.slice(0,begin)+`  @Builder
  comicGrid(items: Comic[], isLocal: boolean) {
    Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
      ForEach(items, (item: Comic) => {
        Column() {
          ComicCell({
            title: item.title,
            subtitle: item.subtitle,
            coverUrl: item.cover,
            sourceKey: item.sourceKey,
            comicId: item.id,
            onTapCell: () => {
              this.openComic(isLocal ? 'local' : item.sourceKey, item.id, item.title, item.cover);
            }
          })
        }.width('31%').margin({ bottom: 18 })
      }, (item: Comic) => \`\${isLocal ? 'local' : item.sourceKey}@\${item.id}\`)
    }.padding({ left: 20, right: 20 }).width('100%')
  }
`+ui.slice(end);
 ui=ui.replace('Row().height(24)','Row().height(UiTheme.bottomInset)');
 ui=ui.replaceAll(".fontColor('#999999')",'.fontColor(UiTheme.muted)');
 ui=ui.replace(/\.height\('100%'\)\s*\n  }\n}/,".height('100%').backgroundColor(UiTheme.page)\n  }\n}");
 return imports(prefix+ui);
});
change('entry/src/main/ets/features/BookshelfView.ets',text=>{
 const [prefix,original]=splitUI(text);let ui=original;
 ui=ui.replace('Row({ space: 10 }) {\n      Text(\'新建收藏夹\')',"Flex({ wrap: FlexWrap.Wrap }) {\n      Text('新建收藏夹')");
 ui=ui.replace('Row({ space: 12 }) {\n      Text(`已选', 'Flex({ wrap: FlexWrap.Wrap }) {\n      Text(`已选');
 ui=ui.replaceAll(".fontSize(13).fontColor('#0A59F7')",".fontSize(13).fontColor(UiTheme.accent).height(42).padding({ left: 10, right: 10 }).borderRadius(13).backgroundColor(UiTheme.surface).margin({ right: 4, bottom: 4 })");
 ui=ui.replace(".fontColor(this.currentFolder.length === 0 ? '#BBBBBB' : '#0A59F7')",".fontColor(this.currentFolder.length === 0 ? '#BBBBBB' : UiTheme.accent).height(42).padding({ left: 10, right: 10 }).borderRadius(13).backgroundColor(UiTheme.surface).margin({ right: 4, bottom: 4 })");
 ui=ui.replace(".fontColor(this.currentFolder.length === 0 ? '#BBBBBB' : '#D93025')",".fontColor(this.currentFolder.length === 0 ? '#BBBBBB' : UiTheme.danger).height(42).padding({ left: 10, right: 10 }).borderRadius(13).backgroundColor(UiTheme.surface).margin({ right: 4, bottom: 4 })");
 ui=ui.replaceAll('      Blank()\n','');
 ui=ui.replaceAll('left: 12, right: 12','left: 20, right: 20').replaceAll('left: 16, right: 16','left: 20, right: 20');
 ui=ui.replaceAll('.height(32)','.height(44)').replaceAll('.height(36)','.height(44)').replaceAll('.height(38)','.height(44)');
 ui=ui.replaceAll('.borderRadius(16)','.borderRadius(18)');
 ui=ui.replaceAll(".fontColor('#666666')",'.fontColor(UiTheme.secondary)');
 ui=ui.replaceAll(".fontColor('#999999')",'.fontColor(UiTheme.muted)');
 ui=ui.replace(/Button\('网络收藏'\)\.fontSize\(12\)/,"Button('网络收藏').attributeModifier(UiStyles.quiet).layoutWeight(1)");
 ui=ui.replace(/Button\('图片收藏'\)\.fontSize\(12\)/,"Button('图片收藏').attributeModifier(UiStyles.quiet).layoutWeight(1)");
 ui=ui.replace(/Button\('手动追更'\)\.fontSize\(12\)/,"Button('手动追更').attributeModifier(UiStyles.quiet).layoutWeight(1)");
 ui=ui.replace("Button('刷新')","Button('刷新').attributeModifier(UiStyles.secondary)");
 ui=ui.replaceAll("Button('取消')","Button('取消').attributeModifier(UiStyles.secondary)");
 ui=ui.replace(".backgroundColor('#FFFFFF')\n  }", ".backgroundColor(UiTheme.surface).borderRadius(24).margin({ left: 20, right: 20, bottom: 12 })\n  }");
 ui=ui.replace(/\.height\('100%'\)\s*\n  }\n}/,".height('100%').backgroundColor(UiTheme.page).padding({ bottom: UiTheme.bottomInset })\n  }\n}");
 return imports(prefix+ui);
});
change('entry/src/main/ets/features/ExploreView.ets',text=>{
 const [prefix,original]=splitUI(text);let ui=original;
 ui=ui.replace(".font({ size: 14 })",".font({ size: 14 }).height(48).borderRadius(18).backgroundColor(UiTheme.surface)");
 ui=ui.replace("Button('刷新')","Button('刷新').attributeModifier(UiStyles.secondary)");
 ui=ui.replace('.height(34)','.height(44)').replaceAll('left: 12, right: 12','left: 20, right: 20');
 ui=ui.replace(".backgroundColor(this.pageIndex === index ? '#E8F0FE' : Color.Transparent)",".backgroundColor(this.pageIndex === index ? UiTheme.accentSoft : UiTheme.surface)");
 ui=ui.replace('.borderRadius(14)','.borderRadius(16)').replace('top: 6, bottom: 6','top: 12, bottom: 12');
 ui=ui.replace(/\.height\('100%'\)\s*\n  }\n}/,".height('100%').backgroundColor(UiTheme.page).padding({ bottom: UiTheme.bottomInset })\n  }\n}");
 return imports(prefix+ui);
});
change('entry/src/main/ets/features/CategoryView.ets',text=>{
 const at=text.indexOf('  build()');const prefix=text.slice(0,at);let ui=text.slice(at);
 ui=ui.replace(".font({ size: 14 }).layoutWeight(1)",".font({ size: 14 }).height(48).borderRadius(18).backgroundColor(UiTheme.surface).layoutWeight(1)");
 ui=ui.replace("Button('刷新').height(34).fontSize(13)","Button('刷新').attributeModifier(UiStyles.secondary)");
 ui=ui.replace("}.width('100%').padding(12)","}.width('100%').padding({ left: 20, right: 20, top: 4, bottom: 16 })");
 ui=ui.replace("Button('排行榜').width('100%')","Button('排行榜').attributeModifier(UiStyles.quiet).width('100%')");
 ui=ui.replace("Text(part.title).fontSize(14).fontWeight(FontWeight.Medium)","Text(part.title).fontSize(17).fontWeight(FontWeight.Bold).fontColor(UiTheme.ink)");
 ui=ui.replace(".borderRadius(6).padding({ left: 10, right: 10, top: 6, bottom: 6 })",".borderRadius(14).padding({ left: 14, right: 14, top: 12, bottom: 12 })");
 ui=ui.replace("}.alignItems(HorizontalAlign.Start).width('100%').padding(16)","}.alignItems(HorizontalAlign.Start).width('100%').padding(18).backgroundColor(UiTheme.surface).borderRadius(24)");
 ui=ui.replace("}.width('100%')\n        }.layoutWeight", "}.width('100%').padding({ left: 20, right: 20, bottom: 8 })\n        }.layoutWeight");
 ui=ui.replace("}.width('100%').height('100%')","}.width('100%').height('100%').backgroundColor(UiTheme.page).padding({ bottom: UiTheme.bottomInset })");
 return imports(prefix+ui);
});
console.log('UI_PRIMARY_REFRESH_APPLIED: only builder/build blocks and presentation imports');
