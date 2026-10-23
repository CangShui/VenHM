import { uiIconSize, uiIconTintMatrix } from './UiIconMetrics';

/** Presentation-only visual tokens. Never import source/network/storage services here. */
export class UiTheme {
  static readonly page: string = '#F4F5F8';
  static readonly surface: string = '#FFFFFF';
  static readonly ink: string = '#171A21';
  static readonly muted: string = '#8B919D';
  static readonly secondary: string = '#646C7A';
  static readonly line: string = '#EBEEF3';
  static readonly accent: string = '#087FF5';
  static readonly accentSoft: string = '#E8F2FF';
  static readonly danger: string = '#D44E5A';
  static readonly dangerSoft: string = '#FFF0F1';
  static readonly success: string = '#05AA7B';
  static readonly cardRadius: number = 24;
  static readonly controlRadius: number = 16;
  static readonly gutter: number = 20;
  static readonly buttonHeight: number = 44;
  static readonly bottomInset: number = 108;
}

/** Legacy 24-unit commands retained for local design-preview compatibility only. */
export function uiIconPath(name: string): string {
  switch (name) {
    case 'home': return 'M3 10 L12 3 L21 10 M5 9 L5 21 L10 21 L10 14 L14 14 L14 21 L19 21 L19 9';
    case 'book': return 'M12 5 C9 3 5 3 2 5 L2 20 C5 18 9 18 12 20 C15 18 19 18 22 20 L22 5 C19 3 15 3 12 5 L12 20';
    case 'layers': return 'M3 7 L12 2 L21 7 L12 12 Z M3 12 L12 17 L21 12 M3 17 L12 22 L21 17';
    case 'settings': return 'M9 3 L15 3 L16 6 L19 7 L22 11 L20 14 L20 18 L16 20 L13 19 L10 21 L6 19 L5 16 L2 14 L3 9 L6 8 L7 5 Z M16 12 A4 4 0 1 1 8 12 A4 4 0 1 1 16 12';
    case 'search': return 'M18 10 A7 7 0 1 1 4 10 A7 7 0 1 1 18 10 M16 16 L22 22';
    case 'history': return 'M4 7 A9 9 0 1 1 3 14 M4 2 L4 7 L9 7 M12 7 L12 12 L16 14';
    case 'folder': return 'M3 6 L9 6 L11 8 L21 8 L21 20 L3 20 Z M3 6 L3 4 L9 4 L11 6 L19 6 L21 8';
    case 'bookmark': return 'M6 3 L18 3 L18 22 L12 18 L6 22 Z';
    case 'cloud': return 'M7 18 L18 18 C24 18 24 9 18 9 C17 1 5 1 4 10 C-1 11 0 18 7 18';
    case 'image': return 'M3 3 L21 3 L21 21 L3 21 Z M3 17 L9 11 L14 16 L17 12 L21 16 M17 7 A1 1 0 1 1 15 7 A1 1 0 1 1 17 7';
    case 'download': return 'M12 3 L12 16 M7 11 L12 16 L17 11 M3 16 L3 21 L21 21 L21 16';
    case 'chart': return 'M4 21 L4 13 M10 21 L10 7 M16 21 L16 3 M22 21 L22 10';
    case 'globe': return 'M22 12 A10 10 0 1 1 2 12 A10 10 0 1 1 22 12 M2 12 L22 12 M12 2 C6 7 6 17 12 22 C18 17 18 7 12 2';
    case 'refresh': return 'M20 8 A9 9 0 0 0 4 6 L2 9 M2 4 L2 9 L7 9 M4 16 A9 9 0 0 0 20 18 L22 15 M17 15 L22 15 L22 20';
    case 'plus': return 'M12 3 L12 21 M3 12 L21 12';
    case 'back': return 'M15 4 L7 12 L15 20';
    case 'chevron': return 'M9 5 L16 12 L9 19';
    case 'filter': return 'M3 4 L21 4 L14 12 L14 21 L10 18 L10 12 Z';
    case 'heart': return 'M12 21 L3 12 C-2 4 8 -1 12 6 C16 -1 26 4 21 12 Z';
    case 'info': return 'M22 12 A10 10 0 1 1 2 12 A10 10 0 1 1 22 12 M12 11 L12 18 M12 6 L12 7';
    case 'shield': return 'M12 2 L21 6 L20 14 C19 18 15 21 12 23 C9 21 5 18 4 14 L3 6 Z M9 12 L11 15 L16 9';
    case 'check': return 'M4 12 L9 17 L21 5';
    case 'message': return 'M3 3 L21 3 L21 17 L12 17 L6 22 L6 17 L3 17 Z M7 8 L17 8 M7 12 L14 12';
    default: return 'M5 5 L10 5 L10 10 L5 10 Z M14 5 L19 5 L19 10 L14 10 Z M5 14 L10 14 L10 19 L5 19 Z M14 14 L19 14 L19 19 L14 19 Z';
  }
}

/** Static resource references are resolved and packaged by the resource compiler. */
export function uiIconResource(name: string): Resource {
  switch (name) {
    case 'home': return $r('app.media.ui_icon_home');
    case 'book': return $r('app.media.ui_icon_book');
    case 'layers': return $r('app.media.ui_icon_layers');
    case 'settings': return $r('app.media.ui_icon_settings');
    case 'search': return $r('app.media.ui_icon_search');
    case 'history': return $r('app.media.ui_icon_history');
    case 'folder': return $r('app.media.ui_icon_folder');
    case 'bookmark': return $r('app.media.ui_icon_bookmark');
    case 'cloud': return $r('app.media.ui_icon_cloud');
    case 'image': return $r('app.media.ui_icon_image');
    case 'download': return $r('app.media.ui_icon_download');
    case 'chart': return $r('app.media.ui_icon_chart');
    case 'globe': return $r('app.media.ui_icon_globe');
    case 'refresh': return $r('app.media.ui_icon_refresh');
    case 'plus': return $r('app.media.ui_icon_plus');
    case 'back': return $r('app.media.ui_icon_back');
    case 'chevron': return $r('app.media.ui_icon_chevron');
    case 'filter': return $r('app.media.ui_icon_filter');
    case 'heart': return $r('app.media.ui_icon_heart');
    case 'info': return $r('app.media.ui_icon_info');
    case 'shield': return $r('app.media.ui_icon_shield');
    case 'check': return $r('app.media.ui_icon_check');
    case 'message': return $r('app.media.ui_icon_message');
    case 'grid': return $r('app.media.ui_icon_grid');
    default: return $r('app.media.ui_icon_grid');
  }
}

@Component
export struct UiIcon {
  @Prop name: string = 'book';
  @Prop color: string = '#171A21';
  @Prop iconSize: number = 24;
  build() {
    // The glyph viewport is independent of the caller's 44/46vp touch target.
    Stack({ alignContent: Alignment.Center }) {
      Image(uiIconResource(this.name))
        .objectFit(ImageFit.Contain)
        .colorFilter(new ColorFilter(uiIconTintMatrix(this.color)))
        .width(uiIconSize(this.iconSize)).height(uiIconSize(this.iconSize))
        .constraintSize({
          minWidth: uiIconSize(this.iconSize), maxWidth: uiIconSize(this.iconSize),
          minHeight: uiIconSize(this.iconSize), maxHeight: uiIconSize(this.iconSize)
        })
    }.width(uiIconSize(this.iconSize)).height(uiIconSize(this.iconSize))
      .constraintSize({
        minWidth: uiIconSize(this.iconSize), maxWidth: uiIconSize(this.iconSize),
        minHeight: uiIconSize(this.iconSize), maxHeight: uiIconSize(this.iconSize)
      })
      .flexGrow(0).flexShrink(0)
      .hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
  }
}

@Component
export struct UiPageHeader {
  @Prop title: string = '';
  @Prop subtitle: string = '';
  @Prop back: boolean = true;
  onBack: () => void = (): void => {};
  build() {
    Column({ space: 12 }) {
      if (this.back) {
        Button({ type: ButtonType.Circle }) { UiIcon({ name: 'back', iconSize: 21 }) }
          .width(44).height(44).backgroundColor(UiTheme.surface).accessibilityText('返回')
          .onClick(() => { this.onBack(); })
      }
      Text(this.title).fontSize(30).fontWeight(FontWeight.Bold).fontColor(UiTheme.ink)
        .width('100%').maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
      if (this.subtitle.length > 0) {
        Text(this.subtitle).fontSize(13).fontColor(UiTheme.secondary).width('100%').lineHeight(20)
      }
    }.alignItems(HorizontalAlign.Start).width('100%').padding({ left: 20, right: 20, top: 12, bottom: 20 })
  }
}

@Component
export struct UiSettingsRow {
  @Prop title: string = '';
  @Prop subtitle: string = '';
  @Prop icon: string = 'settings';
  @Prop tint: string = '#087FF5';
  @Prop tone: string = '#E8F2FF';
  @Prop value: string = '';
  @Prop divider: boolean = false;
  onTap: () => void = (): void => {};
  build() {
    Column() {
      Row({ space: 16 }) {
        Stack() { UiIcon({ name: this.icon, color: this.tint, iconSize: 23 }) }
          .width(46).height(46).borderRadius(15).backgroundColor(this.tone)
        Column({ space: 5 }) {
          Text(this.title).fontSize(16).fontWeight(FontWeight.Medium).fontColor(UiTheme.ink)
            .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
          if (this.subtitle.length > 0) {
            Text(this.subtitle).fontSize(12).fontColor(UiTheme.muted).maxLines(2).width('100%')
          }
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        if (this.value.length > 0) { Text(this.value).fontSize(13).fontColor(UiTheme.muted).maxLines(1) }
        UiIcon({ name: 'chevron', iconSize: 17, color: '#A6ACB6' })
      }.width('100%').constraintSize({ minHeight: 82 }).padding({ left: 18, right: 18, top: 14, bottom: 14 })
      if (this.divider) { Divider().color(UiTheme.line).margin({ left: 80, right: 18 }) }
    }.width('100%').backgroundColor(UiTheme.surface).onClick(() => { this.onTap(); })
      .accessibilityText(this.title).accessibilityGroup(true)
  }
}

@Component
export struct UiSectionHeading {
  @Prop title: string = '';
  @Prop detail: string = '';
  build() {
    Row() {
      Text(this.title).fontSize(13).fontWeight(FontWeight.Medium).fontColor(UiTheme.muted).layoutWeight(1)
      if (this.detail.length > 0) { Text(this.detail).fontSize(12).fontColor(UiTheme.muted) }
    }.width('100%').padding({ left: 10, right: 10, top: 24, bottom: 10 })
  }
}
