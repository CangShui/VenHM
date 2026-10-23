'use strict';
const fs=require('node:fs'),path=require('node:path');const file=path.resolve(__dirname,'../entry/src/main/ets/components/ComicWidgets.ets');let text=fs.readFileSync(file,'utf8');
const start=text.indexOf('export struct ComicCell');if(start<0)throw Error('ComicCell missing');let prefix=text.slice(0,start),ui=text.slice(start);
ui=ui.replace('.borderRadius(8)','.borderRadius(16)');
ui=ui.replace(".fontColor($r('sys.color.font_primary'))",'.fontColor(UiTheme.ink)');
ui=ui.replaceAll(".fontColor($r('sys.color.font_secondary'))",'.fontColor(UiTheme.secondary)');
ui=ui.replace("Text(this.title)\n        .fontSize(13)","Text(this.title)\n        .fontSize(14).fontWeight(FontWeight.Medium).lineHeight(20)");
ui=ui.replace("    Column({ space: 6 }) {","    Column({ space: 9 }) {");
ui=ui.replace('      LoadingProgress().width(36).height(36)','      LoadingProgress().width(32).height(32).color(UiTheme.accent)');
const old=`    Column() {
      Text(this.message)
        .fontSize(14)
        .fontColor(UiTheme.secondary)
        .textAlign(TextAlign.Center)
        .padding({ left: 32, right: 32 })
    }`;
const next=`    Column({ space: 16 }) {
      Stack() { UiIcon({ name: 'folder', color: '#70AFE9', size: 68 }) }
        .width(128).height(128).backgroundColor('#EAF2FD').borderRadius(38)
      Text('这里还没有内容').fontSize(19).fontWeight(FontWeight.Bold).fontColor(UiTheme.ink)
      Text(this.message)
        .fontSize(13).lineHeight(22)
        .fontColor(UiTheme.secondary)
        .textAlign(TextAlign.Center)
        .padding({ left: 32, right: 32 })
    }`;
if(!ui.includes(old))throw Error('EmptyView boundary missing');ui=ui.replace(old,next);
ui=ui.replace("      Button('重试')\n        .fontSize(14)","      Button('重试').attributeModifier(UiStyles.secondary)\n        .fontSize(14)");
// Preserve all request lifecycle and image rendering before ComicCell verbatim.
fs.writeFileSync(file,prefix+ui);console.log('UI_COMMON_WIDGETS_APPLIED image pipeline and callbacks unchanged');
