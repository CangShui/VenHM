'use strict';
const fs=require('node:fs'),path=require('node:path');const root=path.resolve(__dirname,'..');
const file=path.join(root,'entry/src/main/ets/features/SearchView.ets');let text=fs.readFileSync(file,'utf8');
if(text.includes("from '../components/UiModifiers'"))throw Error('Search already styled');
const start=text.indexOf('  @Builder');let prefix=text.slice(0,start),ui=text.slice(start);
const selector=`      Row({ space: 8 }) {
        Select(this.sourceOptions.map((label: string): SelectOption => {
          const option: SelectOption = { value: label }; return option;
        }))
          .selected(this.selectedIndex)
          .value(this.selectedIndex >= 0 ? this.sourceOptions[this.selectedIndex] : '所选源不可用')
          .font({ size: 14 })
          .onSelect((index: number) => { this.selectSource(index); })
        TextInput`;
const replacement=`      Column({ space: 12 }) {
        Row({ space: 10 }) {
          UiIcon({ name: 'globe', size: 19, color: UiTheme.secondary })
          Select(this.sourceOptions.map((label: string): SelectOption => {
            const option: SelectOption = { value: label }; return option;
          }))
            .selected(this.selectedIndex)
            .value(this.selectedIndex >= 0 ? this.sourceOptions[this.selectedIndex] : '所选源不可用')
            .font({ size: 14 }).layoutWeight(1).height(48).backgroundColor(UiTheme.surface)
            .onSelect((index: number) => { this.selectSource(index); })
        }.width('100%').padding({ left: 14, right: 8 }).backgroundColor(UiTheme.surface).borderRadius(18)
        Row({ space: 10 }) {
        TextInput`;
if(!ui.includes(selector))throw Error('Search source selector anchor not found');ui=ui.replace(selector,replacement);
ui=ui.replace(".layoutWeight(1).height(38).fontSize(14)",".layoutWeight(1).height(48).fontSize(15).borderRadius(18).backgroundColor(UiTheme.surface).padding({ left: 18, right: 18 })");
ui=ui.replace("Button('搜索').fontSize(14).height(38)","Button('搜索').attributeModifier(UiStyles.primary).width(80).height(48)");
ui=ui.replace("      }.width('100%').padding({ left: 12, right: 12, top: 8, bottom: 8 })","        }.width('100%')\n      }.width('100%').padding({ left: 20, right: 20, bottom: 16 })");
ui=ui.replaceAll('left: 12, right: 12','left: 20, right: 20');
ui=ui.replace("Button('更多').fontSize(12).height(30)","Button('更多').attributeModifier(UiStyles.quiet)");
ui=ui.replace("Button('重试此源').height(30)","Button('重试此源').attributeModifier(UiStyles.secondary)");
ui=ui.replace("Button('刷新筛选')","Button('刷新筛选').attributeModifier(UiStyles.secondary)");
ui=ui.replace(".fontSize(13).height(32)",".attributeModifier(UiStyles.quiet)");
ui=ui.replace("Button('清空').fontSize(12).height(30)","Button('清空').attributeModifier(UiStyles.quiet)");
ui=ui.replace("Button('删除').fontSize(12).height(28)","Button('删除').attributeModifier(UiStyles.danger)");
ui=ui.replace("Text(entry.term).fontSize(14).layoutWeight(1).maxLines(1)","Text(entry.term).fontSize(14).fontColor(UiTheme.ink).layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })");
ui=ui.replace("                }.width('100%')","                }.width('100%').padding({ left: 16, right: 12, top: 8, bottom: 8 }).backgroundColor(UiTheme.surface)");
ui=ui.replace("}.cachedCount(1).height(220).width('100%')","}.cachedCount(1).height(220).width('calc(100% - 40vp)').borderRadius(24).clip(true)");
ui=ui.replace("}.width('100%').padding(12)","}.width('100%').padding(16).backgroundColor(UiTheme.surface).borderRadius(24).margin({ bottom: 12 })");
ui=ui.replace(".borderRadius(6).padding({ left: 10, right: 10, top: 6, bottom: 6 })",".borderRadius(13).padding({ left: 14, right: 14, top: 12, bottom: 12 })");
ui=ui.replaceAll(".fontColor('#666666')",'.fontColor(UiTheme.secondary)').replaceAll(".fontColor('#777777')",'.fontColor(UiTheme.muted)');
ui=ui.replace("Text('搜索历史').fontSize(13).fontWeight(FontWeight.Medium)","Text('搜索历史').fontSize(16).fontWeight(FontWeight.Bold).fontColor(UiTheme.ink)");
ui=ui.replace("}.cachedCount(1).layoutWeight(1).width('100%')","}.cachedCount(1).layoutWeight(1).width('100%').padding({ left: 20, right: 20, bottom: 24 }).scrollBar(BarState.Off)");
ui=ui.replace("        Button(this.loadingMore ? '加载中…' : (this.ended ? '已到末页' : '加载更多'))","        Button(this.loadingMore ? '加载中…' : (this.ended ? '已到末页' : '加载更多')).attributeModifier(UiStyles.secondary).margin({ bottom: 16 })");
ui=ui.replace("}.width('100%').height('100%')","}.width('100%').height('100%').backgroundColor(UiTheme.page)");
text="import { UiTheme, UiIcon } from '../components/UiKit';\nimport { UiStyles } from '../components/UiModifiers';\n"+prefix+ui;fs.writeFileSync(file,text);
console.log('UI_SEARCH_REFRESH_APPLIED: all source/filter/search/history handlers preserved');
