import { UiTheme } from './UiKit';
import { UiStyles } from './UiModifiers';
import { UiAction, UiBridge, UiRequest } from '../source/UiBridge';
import { AsyncComicImage } from './ComicWidgets';
import { JsEngine } from '../source/JsEngine';
import { Log } from '../foundation/Log';

/**
 * Renders the pending `UI.*` request. Upstream used Flutter's `ContentDialog`
 * plus `_JSCallbackButton` (lib/components/js_ui.dart): a button awaits the
 * script callback and shows a spinner until it resolves, and an input dialog
 * keeps the error returned by the validator.
 */
@Component
export struct VeneraUiDialog {
  @State request: UiRequest | undefined = undefined;
  @State draft: string = '';
  @State error: string = '';
  @State busy: boolean = false;
  @State selected: number = -1;

  aboutToAppear(): void {
    const request = UiBridge.currentRequest();
    this.request = request;
    if (request !== undefined) {
      this.selected = request.initialIndex;
      Log.audit(request.traceId, '前端渲染', `类型=${request.kind}；默认选项=${request.initialIndex}`);
    }
  }

  private async runAction(action: UiAction, index: number): Promise<void> {
    if (this.busy) {
      Log.audit(this.request?.traceId ?? 'ui-dialog', '前端拦截', '上个按钮回调尚未完成，忽略重复点击');
      return;
    }
    const trace = this.request?.traceId ?? 'ui-dialog';
    Log.audit(trace, '用户操作', `点击对话框按钮索引=${index}；有回调=${action.callback !== undefined}`);
    // Upstream keeps the dialog open until the callback's promise settles.
    if (action.callback !== undefined) {
      this.busy = true;
      try {
        await JsEngine.invokeFunction(action.callback, [], trace);
        Log.audit(trace, '回调完成', '脚本按钮回调已等待完成，准备关闭对话框');
      } catch (error) {
        Log.audit(trace, '回调异常', '按钮回调失败；错误原文可能回显输入/会话，未写日志');
      } finally {
        this.busy = false;
      }
    }
    UiBridge.finishDialog(index);
  }

  private actionColor(action: UiAction): string {
    if (action.style === 'danger') {
      return '#D93025';
    }
    return action.style === 'filled' ? '#0A59F7' : '#333333';
  }

  private async confirmInput(): Promise<void> {
    if (this.busy) {
      Log.audit(this.request?.traceId ?? 'ui-input', '前端拦截', '正在校验，忽略重复提交');
      return;
    }
    const request = this.request;
    if (request === undefined) {
      return;
    }
    const value = this.draft;
    Log.audit(request.traceId, '输入校验', `提交长度=${value.length}；有校验函数=${request.validator !== undefined}；内容不落盘`);
    if (request.validator !== undefined) {
      this.busy = true;
      try {
        const result = await JsEngine.invokeFunction(request.validator, [value], request.traceId);
        // A non-empty return value is the error message to display.
        if (result !== null && result !== undefined && String(result).length > 0) {
          this.error = String(result);
          Log.audit(request.traceId, '校验拒绝', '脚本校验未通过，保留输入框，不结算Promise');
          return;
        }
      } catch (error) {
        this.error = error instanceof Error ? error.message : String(error);
        Log.audit(request.traceId, '校验异常', '调用脚本校验函数失败，保留输入框');
        return;
      } finally {
        this.busy = false;
      }
    }
    this.error = '';
    Log.audit(request.traceId, '校验通过', '准备把输入结果交还脚本，内容不落盘');
    UiBridge.finishInput(value);
  }

  @Builder
  titleRow(title: string) {
    Row() {
      Text(title).fontSize(20).fontWeight(FontWeight.Medium).layoutWeight(1)
    }
    .width('100%')
  }

  @Builder
  dialogBody(request: UiRequest) {
    Column({ space: 12 }) {
      this.titleRow(request.title)
      if (request.content.length > 0) {
        Text(request.content).fontSize(14).fontColor(UiTheme.secondary).width('100%')
      }
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.End }) {
        if (request.actions.length === 0) {
          Button('确定').attributeModifier(UiStyles.primary).margin({ left: 8, bottom: 8 })
            .fontSize(14)
            .onClick(() => {
              UiBridge.finishDialog(-1);
            })
        } else {
          ForEach(request.actions, (action: UiAction, index: number) => {
            Button(this.busy ? '处理中…' : action.text).attributeModifier(UiStyles.secondary).margin({ left: 8, bottom: 8 })
              .fontSize(14)
              .fontColor(action.style === 'danger' ? UiTheme.danger : (action.style === 'filled' ? '#FFFFFF' : UiTheme.ink))
              .backgroundColor(action.style === 'danger' ? UiTheme.dangerSoft : (action.style === 'filled' ? UiTheme.accent : '#EDF0F5'))
              .enabled(!this.busy)
              .onClick(() => {
                this.runAction(action, index);
              })
          }, (action: UiAction, index: number) => `action-${index}-${action.text}`)
        }
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  inputBody(request: UiRequest) {
    Column({ space: 12 }) {
      this.titleRow(request.title)
      if (request.imageUrl.length > 0) {
        Column() {
          AsyncComicImage({ url: request.imageUrl, objectFit: ImageFit.Contain })
        }
        .width('100%')
        .height(140)
        .borderRadius(16)
        .clip(true)
      }
      TextInput({ placeholder: '请输入', text: this.draft })
        .height(48)
        .fontSize(14)
        .width('100%')
        .onChange((value: string) => {
          this.draft = value;
            Log.audit(request.traceId, '前端输入', `输入长度变为${value.length}；内容不落盘`);
          if (this.error.length > 0) {
            this.error = '';
          }
        })
      if (this.error.length > 0) {
        Text(this.error).fontSize(12).fontColor('#D93025').width('100%')
      }
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.End }) {
        Button('取消').attributeModifier(UiStyles.secondary).margin({ left: 8, bottom: 8 })
          .fontSize(14).backgroundColor('#F1F3F5').fontColor('#333333')
          .onClick(() => {
            UiBridge.cancelAnswer();
          })
        Button(this.busy ? '校验中…' : '确定').attributeModifier(UiStyles.primary).margin({ left: 8, bottom: 8 })
          .fontSize(14)
          .enabled(!this.busy)
          .onClick(() => {
            this.confirmInput();
          })
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  selectBody(request: UiRequest) {
    Column({ space: 8 }) {
      this.titleRow(request.title)
      List({ space: 4 }) {
        ForEach(request.options, (option: string, index: number) => {
          ListItem() {
            Row({ space: 8 }) {
              Text(this.selected === index ? '●' : '○')
                .fontSize(14)
                .fontColor(this.selected === index ? '#0A59F7' : '#BBBBBB')
              Text(option).fontSize(14).layoutWeight(1)
            }
            .width('100%')
            .padding({ top: 10, bottom: 10 })
            .onClick(() => {
              this.selected = index;
              UiBridge.finishSelect(index);
            })
          }
        }, (option: string, index: number) => `option-${index}-${option}`)
      }
      .width('100%')
      .height(220)

      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.End }) {
        Button('取消').attributeModifier(UiStyles.secondary).margin({ left: 8, bottom: 8 })
          .fontSize(14).backgroundColor('#F1F3F5').fontColor('#333333')
          .onClick(() => {
            UiBridge.cancelAnswer();
          })
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  loadingBody(request: UiRequest) {
    Column({ space: 14 }) {
      LoadingProgress().width(36).height(36)
      Text(request.title).fontSize(14).fontColor(UiTheme.secondary)
      if (request.onCancel !== undefined) {
        Button('取消').attributeModifier(UiStyles.secondary).margin({ left: 8, bottom: 8 })
          .fontSize(14).backgroundColor('#F1F3F5').fontColor('#333333')
          .onClick(() => {
            UiBridge.cancelLoadingRequest();
          })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }

  build() {
    Column() {
      if (this.request !== undefined) {
        if (this.request.kind === 'dialog') {
          this.dialogBody(this.request)
        } else if (this.request.kind === 'input') {
          this.inputBody(this.request)
        } else if (this.request.kind === 'select') {
          this.selectBody(this.request)
        } else {
          this.loadingBody(this.request)
        }
      }
    }
    .width('100%')
    .padding(20)
    .backgroundColor('#FFFFFF')
    .borderRadius(24)
  }
}

