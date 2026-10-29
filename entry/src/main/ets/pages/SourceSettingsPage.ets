import { router, promptAction } from '@kit.ArkUI';
import { AppContext } from '../foundation/AppContext';
import { AppInit } from '../foundation/AppInit';
import { Log } from '../foundation/Log';
import { SourceManager } from '../source/SourceManager';
import { SourceSettings, SourceSettingField, SourceSettingOption } from '../source/SourceSettings';
import { UiTheme, UiIcon, UiPageHeader } from '../components/UiKit';
import { UiStyles } from '../components/UiModifiers';

/** Upstream v1.17.0: reread dynamic settings after each save/callback. */
@Entry
@Component
struct SourceSettingsPage {
  @State sourceKey: string = '';
  @State sourceName: string = '';
  @State fields: SourceSettingField[] = [];
  @State drafts: Map<string, string> = new Map<string, string>();
  @State loading: boolean = true;
  @State error: string = '';
  @State saved: Record<string, Object> = {};
  @State busyKey: string = '';
  @State schemaRevision: number = 0;
  private loadVersion: number = 0;
  private disposed: boolean = false;

  aboutToAppear(): void {
    this.disposed = false;
    AppContext.ensureInitialized(this.getUIContext().getHostContext());
    const params = router.getParams() as Record<string, Object>;
    const key = params === null || params === undefined ? undefined : params['key'];
    if (typeof key !== 'string' || key.length === 0) {
      this.error = '缺少漫画源 key';
      this.loading = false;
      return;
    }
    this.sourceKey = key;
    this.loadSettings();
  }

  aboutToDisappear(): void {
    this.disposed = true;
    this.loadVersion++;
  }

  private async loadSettings(trace: string = `settings-load-${Date.now()}`): Promise<void> {
    const version = ++this.loadVersion;
    this.loading = true;
    try {
      await AppInit.init();
      const source = SourceManager.find(this.sourceKey);
      if (source === undefined) {
        throw new Error(`未加载漫画源：${this.sourceKey}`);
      }
      const fields = await SourceSettings.read(this.sourceKey, trace);
      if (this.disposed || version !== this.loadVersion) {
        Log.audit(trace, '页面拦截', '页面已退出或有更新的读取请求，丢弃迟到结果');
        return;
      }
      this.sourceName = source.name;
      this.saved = SourceSettings.settingsOf(this.sourceKey);
      this.fields = fields;
      // Recreate rows to replace callbacks that captured the old schema.
      this.schemaRevision++;
      this.error = '';
      Log.audit(trace, '页面显示', `动态字段已刷新，字段数=${fields.length}；未清空其他输入草稿`);
    } catch (error) {
      if (!this.disposed && version === this.loadVersion) {
        this.error = error instanceof Error ? error.message : String(error);
      }
      Log.audit(trace, '页面异常', '源设置读取失败，错误显示在页面，不记录设置内容');
    } finally {
      if (!this.disposed && version === this.loadVersion) {
        this.loading = false;
      }
    }
  }

  private effective(field: SourceSettingField): Object | undefined {
    return SourceSettings.effective(field, this.saved);
  }

  private displayText(field: SourceSettingField): string {
    const value = this.effective(field);
    return value === null || value === undefined ? '' : String(value);
  }

  private selectedIndex(field: SourceSettingField): number {
    return SourceSettings.selectedIndex(field, this.saved);
  }

  private selectionText(field: SourceSettingField): string {
    const index = this.selectedIndex(field);
    return index >= 0 ? field.options[index].text
      : (this.displayText(field).length > 0 ? `当前值：${this.displayText(field)}` : '请选择');
  }

  private async saveValue(field: SourceSettingField, value: Object, validate: boolean): Promise<void> {
    const trace = `settings-save-${Date.now()}-${field.key}`;
    Log.audit(trace, '用户操作', `源=${this.sourceKey}；键=${field.key}；类型=${typeof value}；内容不落盘`);
    if (this.busyKey.length > 0 || this.loading || this.disposed) {
      Log.audit(trace, '前置拦截', '已有操作、正在刷新或页面已退出；未写入设置');
      return;
    }
    this.busyKey = field.key;
    this.error = '';
    try {
      if (validate) {
        const rejected = await SourceSettings.validate(this.sourceKey, field.key, value as string, trace);
        if (rejected.length > 0) {
          this.error = `${field.title}：${rejected}`;
          return;
        }
      }
      if (this.disposed) {
        Log.audit(trace, '前置拦截', '校验期间页面退出；未写入设置');
        return;
      }
      await SourceSettings.commit(this.sourceKey, field.key, value, trace);
      if (this.disposed) {
        return;
      }
      const drafts = new Map<string, string>(this.drafts);
      drafts.delete(field.key);
      this.drafts = drafts;
      await this.loadSettings(trace);
      if (!this.disposed && this.error.length === 0) {
        promptAction.showToast({ message: '已保存' });
      }
      Log.audit(trace, '响应返回', this.error.length === 0
        ? '持久化成功，动态字段重新读取完成' : '设置已落盘，但动态字段刷新失败，页面保留错误');
    } catch (error) {
      if (!this.disposed) {
        this.error = `${field.title}：${error instanceof Error ? error.message : String(error)}`;
      }
      Log.audit(trace, '操作异常', '保存或刷新失败；保留未提交草稿，不宣称保存成功');
    } finally {
      if (!this.disposed) {
        this.busyKey = '';
      }
    }
  }

  private async saveInput(field: SourceSettingField): Promise<void> {
    await this.saveValue(field, this.drafts.get(field.key) ?? this.displayText(field), true);
  }

  private async choose(field: SourceSettingField, index: number): Promise<void> {
    if (index < 0 || index >= field.options.length) {
      Log.audit(`settings-select-${Date.now()}`, '前置拒绝', '选项索引越界，未写入设置');
      return;
    }
    await this.saveValue(field, field.options[index].value, false);
  }

  private async runCallback(field: SourceSettingField): Promise<void> {
    if (!field.hasCallback || this.busyKey.length > 0 || this.loading || this.disposed) {
      return;
    }
    const trace = `settings-callback-${Date.now()}-${field.key}`;
    this.busyKey = field.key;
    this.error = '';
    try {
      await SourceSettings.runCallback(this.sourceKey, field.key, trace);
      if (!this.disposed) {
        await this.loadSettings(trace);
        if (this.error.length === 0) {
          promptAction.showToast({ message: `${field.title}：操作完成` });
        }
      }
    } catch (error) {
      if (!this.disposed) {
        this.error = `${field.title}：${error instanceof Error ? error.message : String(error)}`;
      }
      Log.audit(trace, '回调异常', '脚本回调失败；页面已显示错误，忙碌状态将解除');
    } finally {
      if (!this.disposed) {
        this.busyKey = '';
      }
    }
  }

  build() {
    Column() {
      UiPageHeader({ title: '源设置', subtitle: this.sourceName || this.sourceKey, onBack: () => { router.back(); } })
      Row() {
        Text('漫画源提供的动态设置').fontSize(13).fontColor(UiTheme.secondary).layoutWeight(1)
        Button('刷新').attributeModifier(UiStyles.quiet)
          .enabled(this.busyKey.length === 0 && !this.loading)
          .onClick(() => { this.loadSettings(); })
      }.width('100%').padding({ left: 24, right: 20, bottom: 16 })
      if (this.error.length > 0) {
        Text(this.error).fontSize(13).fontColor(UiTheme.danger).lineHeight(20).padding(18)
          .width('100%').backgroundColor(UiTheme.dangerSoft).borderRadius(18)
      }
      if (this.loading) {
        Column({ space: 12 }) {
          LoadingProgress().width(32).height(32).color(UiTheme.accent)
          Text('正在读取源设置…').fontSize(14).fontColor(UiTheme.secondary)
        }.width('100%').padding(28).backgroundColor(UiTheme.surface).borderRadius(UiTheme.cardRadius)
      } else if (this.fields.length === 0) {
        Column({ space: 12 }) {
          UiIcon({ name: 'settings', iconSize: 30, color: UiTheme.muted })
          Text('该漫画源没有声明可编辑设置').fontSize(14).fontColor(UiTheme.secondary)
        }.width('100%').padding(28).backgroundColor(UiTheme.surface).borderRadius(UiTheme.cardRadius)
      } else {
        List({ space: 12 }) {
          ForEach(this.fields, (field: SourceSettingField) => {
            ListItem() {
              Column({ space: 14 }) {
                Text(field.title).fontSize(16).fontWeight(FontWeight.Medium).fontColor(UiTheme.ink).width('100%')
                if (field.schemaError.length > 0) {
                  Text(`设置定义错误：${field.schemaError}`).fontSize(12).fontColor(UiTheme.danger).lineHeight(20)
                } else if (field.type === 'input') {
                  Column({ space: 12 }) {
                    TextInput({ text: this.drafts.get(field.key) ?? this.displayText(field) })
                      .width('100%').height(50).fontSize(14).backgroundColor(UiTheme.page).borderRadius(14).enabled(this.busyKey.length === 0)
                      .onChange((text: string) => {
                        const drafts = new Map<string, string>(this.drafts);
                        drafts.set(field.key, text);
                        this.drafts = drafts;
                      })
                    Button(this.busyKey === field.key ? '保存中…' : '保存')
                      .attributeModifier(UiStyles.primary).enabled(this.busyKey.length === 0)
                      .onClick(() => { this.saveInput(field); })
                  }.alignItems(HorizontalAlign.Start).width('100%')
                } else if (field.type === 'select' && field.options.length > 0) {
                  Select(field.options.map((option: SourceSettingOption) => {
                    const item: SelectOption = { value: option.text };
                    return item;
                  }))
                    .selected(this.selectedIndex(field)).value(this.selectionText(field))
                    .height(48).font({ size: 14 }).fontColor(UiTheme.ink).backgroundColor(UiTheme.page).borderRadius(14)
                    .enabled(this.busyKey.length === 0)
                    .fontColor(UiTheme.ink).selectedOptionFontColor(UiTheme.accent).optionFontColor(UiTheme.ink).optionBgColor(UiTheme.surface).selectedOptionBgColor(UiTheme.accentSoft).menuBackgroundColor(UiTheme.surface).onSelect((index: number) => { this.choose(field, index); })
                } else if (field.type === 'select') {
                  Text('当前没有可用选项').fontSize(13).fontColor(UiTheme.muted)
                } else if (field.type === 'switch') {
                  Row() {
                    Toggle({ type: ToggleType.Switch, isOn: this.effective(field) === true })
                      .selectedColor(UiTheme.accent).enabled(this.busyKey.length === 0)
                      .onChange((enabled: boolean) => { this.saveValue(field, enabled, false); })
                  }.width('100%').constraintSize({ minHeight: 48 })
                } else if (field.type === 'callback' && field.hasCallback) {
                  Button(this.busyKey === field.key ? '处理中…' : field.buttonText)
                    .attributeModifier(UiStyles.secondary).enabled(this.busyKey.length === 0)
                    .onClick(() => { this.runCallback(field); })
                } else {
                  Text('该设置类型暂不支持或回调无效').fontSize(13).fontColor('#D69A2D')
                }
              }.alignItems(HorizontalAlign.Start).width('100%').constraintSize({ minHeight: 80 }).padding(20)
                .backgroundColor(UiTheme.surface).borderRadius(UiTheme.cardRadius)
            }
          }, (field: SourceSettingField) => `${field.key}-${this.schemaRevision}`)
        }.width('100%').layoutWeight(1).scrollBar(BarState.Off).padding({ left: 20, right: 20, bottom: 24 })
      }
    }.width('100%').height('100%').backgroundColor(UiTheme.page)
  }
}
