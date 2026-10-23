import { UiTheme } from './UiKit';

/** Shared presentation modifiers; no callbacks, storage or network access. */
class PrimaryButtonStyle implements AttributeModifier<ButtonAttribute> {
  applyNormalAttribute(instance: ButtonAttribute): void {
    instance.height(UiTheme.buttonHeight).fontSize(14).fontWeight(FontWeight.Medium)
      .fontColor('#FFFFFF').backgroundColor(UiTheme.accent).borderRadius(15)
      .padding({ left: 18, right: 18 }).constraintSize({ minWidth: 44 });
  }
}
class SecondaryButtonStyle implements AttributeModifier<ButtonAttribute> {
  applyNormalAttribute(instance: ButtonAttribute): void {
    instance.height(UiTheme.buttonHeight).fontSize(14).fontWeight(FontWeight.Medium)
      .fontColor(UiTheme.ink).backgroundColor('#EDF0F5').borderRadius(15)
      .padding({ left: 16, right: 16 }).constraintSize({ minWidth: 44 });
  }
}
class QuietButtonStyle implements AttributeModifier<ButtonAttribute> {
  applyNormalAttribute(instance: ButtonAttribute): void {
    instance.height(40).fontSize(13).fontWeight(FontWeight.Medium)
      .fontColor(UiTheme.accent).backgroundColor(UiTheme.accentSoft).borderRadius(13)
      .padding({ left: 14, right: 14 }).constraintSize({ minWidth: 44 });
  }
}
class DangerButtonStyle implements AttributeModifier<ButtonAttribute> {
  applyNormalAttribute(instance: ButtonAttribute): void {
    instance.height(44).fontSize(13).fontWeight(FontWeight.Medium)
      .fontColor(UiTheme.danger).backgroundColor(UiTheme.dangerSoft).borderRadius(15)
      .padding({ left: 14, right: 14 }).constraintSize({ minWidth: 44 });
  }
}
export class UiStyles {
  static readonly primary: AttributeModifier<ButtonAttribute> = new PrimaryButtonStyle();
  static readonly secondary: AttributeModifier<ButtonAttribute> = new SecondaryButtonStyle();
  static readonly quiet: AttributeModifier<ButtonAttribute> = new QuietButtonStyle();
  static readonly danger: AttributeModifier<ButtonAttribute> = new DangerButtonStyle();
}
