'use strict';
const fs=require('node:fs'),path=require('node:path');const file=path.resolve(__dirname,'../entry/src/main/ets/pages/ReaderPage.ets');let text=fs.readFileSync(file,'utf8');
const top=text.indexOf('  @Builder\n  topBar()'),endTop=text.indexOf('  /** "第 n/N 章',top);if(top<0||endTop<0)throw Error('Top chrome anchors missing');
text=text.slice(0,top)+text.slice(endTop);
const bottom=text.indexOf('  @Builder\n  bottomBar()'),endBottom=text.indexOf('  @Builder\n  flowImage(',bottom);if(bottom<0||endBottom<0)throw Error('Bottom chrome anchors missing');
const menu=`  /** A single bottom overlay. It never participates in the image canvas layout. */
  @Builder
  bottomBar() {
    Scroll() {
      Column({ space: 12 }) {
        Row().width(36).height(4).borderRadius(2).backgroundColor('#69717F').alignSelf(ItemAlign.Center)
        Row({ space: 10 }) {
          Button('返回').height(44).fontSize(13).fontColor('#F1F4FA').backgroundColor('#2B3039')
            .borderRadius(14).padding({ left: 16, right: 16 }).onClick(() => { this.returnToPrevious(); })
          Column({ space: 5 }) {
            Text(this.title).fontSize(15).fontWeight(FontWeight.Medium).fontColor('#F1F4FA')
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
            Text(this.chapterLabel()).fontSize(12).fontColor('#A7B1C1').maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            .onClick(() => {
              if (this.progressReady && !this.loading) { this.showChapters = !this.showChapters; }
            })
          Button('收起').height(44).fontSize(13).fontColor('#C4D9FA').backgroundColor('#2B3039')
            .borderRadius(14).padding({ left: 14, right: 14 }).onClick(() => { this.toolbarVisible = false; })
        }.width('100%')
        Row() {
          Text(this.options.showPageNumberInReader ? this.pageCounter() : '').fontSize(13).fontColor('#DDE5F1').layoutWeight(1)
          if (this.options.enableClockAndBatteryInfoInReader) { Text(this.clockInfo).fontSize(11).fontColor('#9DAABB') }
        }.width('100%')
        Row({ space: 8 }) {
          Button('上一章').height(44).fontSize(13).fontColor('#F2F3F5').backgroundColor('#2B3039').borderRadius(14).layoutWeight(1)
            .enabled(!this.loading && this.progressReady).onClick(() => { this.switchChapter(-1); })
          Button('目录').height(44).fontSize(13).fontColor('#A9CDFF').backgroundColor('#29394E').borderRadius(14).layoutWeight(1)
            .enabled(!this.loading && this.progressReady).onClick(() => { this.showChapters = !this.showChapters; })
          Button('下一章').height(44).fontSize(13).fontColor('#F2F3F5').backgroundColor('#2B3039').borderRadius(14).layoutWeight(1)
            .enabled(!this.loading && this.progressReady).onClick(() => { this.switchChapter(1); })
        }.width('100%')
        Flex({ wrap: FlexWrap.Wrap }) {
          Button('‹页').height(42).fontSize(12).fontColor('#C4D9FA').backgroundColor('#2B3039').borderRadius(13)
            .margin({ right: 8, bottom: 8 }).enabled(this.progressReady && !this.loading && this.adjacentSource(-1) >= 0)
            .onClick(() => { this.stepPage(-1); })
          Button('页›').height(42).fontSize(12).fontColor('#C4D9FA').backgroundColor('#2B3039').borderRadius(13)
            .margin({ right: 8, bottom: 8 }).enabled(this.progressReady && !this.loading && this.adjacentSource(1) >= 0)
            .onClick(() => { this.stepPage(1); })
          Button(this.autoReading ? '暂停' : '自动').height(42).fontSize(12).fontColor('#C4D9FA').backgroundColor('#2B3039').borderRadius(13)
            .margin({ right: 8, bottom: 8 }).enabled(!this.loading && this.progressReady).onClick(() => { this.toggleAutoRead(); })
          Button(ReaderModes.label(this.mode)).height(42).fontSize(12).fontColor('#C4D9FA').backgroundColor('#2B3039').borderRadius(13)
            .margin({ right: 8, bottom: 8 }).enabled(!this.loading && this.progressReady && !this.settingsSaving)
            .onClick(() => { this.setMode(ReaderModes.nextMode(this.mode)); })
          Button('设置').height(42).fontSize(12).fontColor('#C4D9FA').backgroundColor('#2B3039').borderRadius(13)
            .margin({ right: 8, bottom: 8 }).enabled(!this.settingsSaving).onClick(() => { this.openReaderSettings(); })
          Button(this.readerBrightness < 0 ? '亮度' : \`\${Math.round(this.readerBrightness * 100)}%\`)
            .height(42).fontSize(12).fontColor('#C4D9FA').backgroundColor('#2B3039').borderRadius(13)
            .margin({ right: 8, bottom: 8 }).onClick(() => { this.cycleBrightness(); })
          Button('详情').height(42).fontSize(12).fontColor('#C4D9FA').backgroundColor('#2B3039').borderRadius(13)
            .margin({ right: 8, bottom: 8 }).enabled(!this.leavingReader && this.sourceKey.length > 0 && this.comicId.length > 0)
            .onClick(() => { this.openComicDetails(); })
          Button(this.collectingImage ? '收藏中…' : '收藏图片').height(42).fontSize(12).fontColor('#C4D9FA').backgroundColor('#2B3039').borderRadius(13)
            .margin({ right: 8, bottom: 8 }).enabled(this.progressReady && !this.loading && !this.collectingImage)
            .onClick(() => { this.collectPicture(this.currentPage); })
          Button('图片菜单').height(42).fontSize(12).fontColor('#C4D9FA').backgroundColor('#2B3039').borderRadius(13)
            .margin({ right: 8, bottom: 8 }).enabled(this.progressReady && !this.loading)
            .onClick(() => { this.showImageMenu(this.currentPage); })
          Button('统计').height(42).fontSize(12).fontColor('#C4D9FA').backgroundColor('#2B3039').borderRadius(13)
            .margin({ bottom: 8 }).onClick(() => { this.openStatistics(); })
        }.width('100%')
        if (this.volumeError.length > 0) { Text(this.volumeError).fontSize(11).fontColor('#FFCA80').width('100%') }
        if (this.immersiveError.length > 0) { Text(this.immersiveError).fontSize(11).fontColor('#FFCA80').width('100%') }
      }.width('100%').padding({ left: 18, right: 18, top: 12, bottom: 28 }).alignItems(HorizontalAlign.Start)
    }.width('100%').constraintSize({ maxHeight: this.landscape ? '76%' : '58%' })
      .backgroundColor('#F2191D24').borderRadius({ topLeft: 24, topRight: 24 })
      .scrollBar(BarState.Off).transition(TransitionEffect.OPACITY)
  }

`;
text=text.slice(0,bottom)+menu+text.slice(endBottom);
const build=text.indexOf('  build() {');if(build<0)throw Error('Reader build anchor missing');
text=text.slice(0,build)+`  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      // Stable fullscreen canvas. Menu visibility never changes this subtree's
      // geometry, keys, data source, renderGeneration or image request identity.
      Column() {
        if (this.loading) {
          LoadingView({ message: '正在加载章节…' }).layoutWeight(1).backgroundColor('#F5F5F5')
        } else if (this.error.length > 0) {
          ErrorView({ message: this.error, onRetry: () => { this.load(); } })
            .layoutWeight(1).backgroundColor('#F5F5F5')
        } else if (this.images.length === 0) {
          ErrorView({ message: '该章节没有图片' }).layoutWeight(1).backgroundColor('#F5F5F5')
        } else if (ReaderModes.isGallery(this.mode)) {
          this.gallerySwiper()
        } else {
          this.continuousList()
        }
      }.width('100%').height('100%').backgroundColor(Color.Black)
      if (this.toolbarVisible && !this.showChapters) { this.bottomBar() }
      if (this.showChapters && !this.loading && this.error.length === 0) { this.chapterListOverlay() }
    }.width('100%').height('100%').backgroundColor(Color.Black)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .onAreaChange((oldArea: Area, area: Area) => { this.onViewportSize(Number(area.width), Number(area.height)); })
  }
}
`;
fs.writeFileSync(file,text);console.log('READER_BOTTOM_CHROME_APPLIED; no top banner or permanently visible reveal button; fullscreen canvas is independent');
