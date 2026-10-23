'use strict';
const fs=require('node:fs'),path=require('node:path');const root=path.resolve(__dirname,'..');
for(const name of ['LoginDialog','UiDialog']){
 const p=path.join(root,'entry/src/main/ets/components/'+name+'.ets');let source=fs.readFileSync(p,'utf8');if(source.includes("from './UiModifiers'"))throw Error('Dialog already styled');
 const at=source.indexOf(name==='LoginDialog'?'  build()':'  @Builder');if(at<0)throw Error('UI boundary missing '+name);
 let before=source.slice(0,at),ui=source.slice(at);
 ui=ui.replaceAll("Row({ space: 12 })",'Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.End })');
 ui=ui.replaceAll('.height(40)','.height(48)').replaceAll('.height(42)','.height(48)');
 ui=ui.replaceAll("Button('取消')","Button('取消').attributeModifier(UiStyles.secondary).margin({ left: 8, bottom: 8 })");
 ui=ui.replaceAll("Button('确定')","Button('确定').attributeModifier(UiStyles.primary).margin({ left: 8, bottom: 8 })");
 ui=ui.replace("Button('登录')","Button('登录').attributeModifier(UiStyles.primary).margin({ left: 8, bottom: 8 })");
 ui=ui.replace("Button(this.busy ? '校验中…' : '确定')","Button(this.busy ? '校验中…' : '确定').attributeModifier(UiStyles.primary).margin({ left: 8, bottom: 8 })");
 ui=ui.replace("Button(this.busy ? '处理中…' : action.text)","Button(this.busy ? '处理中…' : action.text).attributeModifier(UiStyles.secondary).margin({ left: 8, bottom: 8 })");
 ui=ui.replace(".fontColor(this.actionColor(action) === '#333333' ? '#333333' : '#FFFFFF')",".fontColor(action.style === 'danger' ? UiTheme.danger : (action.style === 'filled' ? '#FFFFFF' : UiTheme.ink))");
 ui=ui.replace(".backgroundColor(this.actionColor(action) === '#333333' ? '#F1F3F5' : this.actionColor(action))",".backgroundColor(action.style === 'danger' ? UiTheme.dangerSoft : (action.style === 'filled' ? UiTheme.accent : '#EDF0F5'))");
 ui=ui.replaceAll('.borderRadius(8)','.borderRadius(16)').replaceAll('.borderRadius(12)','.borderRadius(24)');
 ui=ui.replaceAll(".fontColor('#555555')",'.fontColor(UiTheme.secondary)');
 ui=ui.replaceAll('.fontSize(16)','.fontSize(20)');
 if(name==='LoginDialog')ui=ui.replace('.padding(20)','.padding(24).backgroundColor(UiTheme.surface).borderRadius(24)');
 fs.writeFileSync(p,"import { UiTheme } from './UiKit';\nimport { UiStyles } from './UiModifiers';\n"+before+ui);
}
console.log('UI_DIALOGS_REFRESHED callbacks and validation logic unchanged');
