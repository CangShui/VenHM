import { promptAction, UIContext } from '@kit.ArkUI';
import { JsEngine } from './JsEngine';
import { Log } from '../foundation/Log';

/** One button of `UI.showDialog`, matching upstream's action object. */
export class UiAction {
  text: string = '';
  /** text | filled | danger */
  style: string = 'text';
  /** JS function handle; invoked on tap and awaited before closing. */
  callback?: Object;
}

/**
 * One pending `UI.*` request. Rendered by components/UiDialog.ets; the host
 * component owns the editable state and reports the answer back here.
 */
export class UiRequest {
  kind: string = '';
  title: string = '';
  content: string = '';
  actions: UiAction[] = [];
  options: string[] = [];
  initialIndex: number = -1;
  validator?: Object;
  imageUrl: string = '';
  /// Stable id for showLoading/cancelLoading.
  id: number = 0;
  dialogId: number = -1;
  traceId: string = '';
  cancelled: boolean = false;
  cancelCallbackRunning: boolean = false;
  settled: boolean = false;
  answer: Object | null = null;
  resolver?: (value: Object | null) => void;
  onCancel?: Object;
  /**
   * False when the request must be answered explicitly, so the promise cannot
   * be orphaned by a barrier tap.
   */
  dismissible: boolean = false;
}

/**
 * Bridge between `UI.*` in a comic source and ArkUI dialogs.
 *
 * Dart original: lib/components/js_ui.dart (`JsUiApi`). Upstream shows Flutter
 * dialogs and returns the user's answer to the script; the same is done here
 * with an ArkUI custom dialog. Requests are serialised because a source can
 * ask for several dialogs in a row (login flows do exactly that).
 */
export class UiBridge {
  private static active: UiRequest | undefined = undefined;
  private static tail: Promise<void> = Promise.resolve();
  private static nextLoadingId: number = 0;
  private static readonly loading: Map<number, UiRequest> = new Map<number, UiRequest>();
  private static builder: CustomBuilder | undefined = undefined;
  private static uiContext: UIContext | undefined = undefined;
  private static nextTrace: number = 0;

  /**
   * The dialog UI lives in components/UiDialog.ets, which imports this file.
   * Registering the builder here (instead of importing it back) keeps the
   * dependency one-way.
   */
  static registerBuilder(builder: CustomBuilder, context: UIContext): void {
    UiBridge.builder = builder;
    UiBridge.uiContext = context;
    Log.audit('ui-host', '宿主注册', '组件拥有的Builder与UIContext已注册，后续对话框在同一UI实例打开和关闭');
  }

  static get isReady(): boolean {
    return UiBridge.builder !== undefined;
  }

  static currentRequest(): UiRequest | undefined {
    return UiBridge.active;
  }

  /** Chain a request so two source dialogs never overlap. */
  private static enqueue(request: UiRequest): Promise<Object | null> {
    if (request.traceId.length === 0) { request.traceId = `ui-${Date.now()}-${UiBridge.nextTrace++}`; }
    Log.audit(request.traceId, '请求到达', `类型=${request.kind}；按钮数=${request.actions.length}；选项数=${request.options.length}；不记录用户输入或验证码`);
    const answer: Promise<Object | null> = UiBridge.tail.then(() => UiBridge.present(request));
    // Keep the chain alive even when the user cancels.
    UiBridge.tail = answer.then((): void => {}, (): void => {});
    return answer;
  }

  private static async present(request: UiRequest): Promise<Object | null> {
    if (request.cancelled) {
      Log.audit(request.traceId, '请求被取消', '排队中的加载框已取消，未进入渲染，返回null');
      Log.audit(request.traceId, '响应返回', '排队取消完成；类型=null；队列释放');
      return null;
    }
    UiBridge.active = request;
    const builder = UiBridge.builder;
    const context = UiBridge.uiContext;
    if (builder === undefined || context === undefined) {
      Log.audit(request.traceId, '请求被拒绝', '缺少组件Builder或UIContext，未进入渲染，返回null');
      UiBridge.active = undefined;
      Log.audit(request.traceId, '响应返回', '宿主未就绪；类型=null；队列释放');
      return null;
    }
    const answered = new Promise<Object | null>((resolve: (value: Object | null) => void) => {
      request.resolver = resolve;
    });
    try {
      const options: promptAction.CustomDialogOptions = {
        builder: builder,
        autoCancel: request.dismissible,
        isModal: true,
        onWillDismiss: () => {
          if (request.kind === 'loading' && request.onCancel !== undefined) {
            UiBridge.cancelLoadingRequest();
          }
        }
      };
      Log.audit(request.traceId, '业务执行', '通过宿主UIContext打开对话框，等待设备返回dialogId');
      request.dialogId = await context.getPromptAction().openCustomDialog(options);
      Log.audit(request.traceId, '渲染完成', `对话框ID=${request.dialogId}`);
      // The user/cancelLoading may answer while openCustomDialog is pending.
      // Do not leak the late dialog or resolve the queue before closing it.
      if (request.settled || request.cancelled) {
        UiBridge.complete(request);
      }
    } catch (error) {
      Log.audit(request.traceId, '异常', '打开对话框失败；不记录可能包含标题/输入的原文；返回null，队列继续运行');
      // Never leave the script awaiting a dialog that was never shown.
      request.answer = null;
      request.settled = true;
      UiBridge.complete(request);
    }
    return await answered;
  }

  private static settle(value: Object | null): void {
    const request = UiBridge.active;
    if (request === undefined || request.settled) {
      return;
    }
    request.settled = true;
    request.answer = value;
    Log.audit(request.traceId, '响应准备', `结果类型=${value === null ? 'null/取消' : typeof value}；不记录输入内容`);
    if (request.dialogId >= 0) {
      UiBridge.complete(request);
    }
    // Otherwise present() owns the pending open and closes its late result.
  }

  private static complete(request: UiRequest): void {
    if (request.dialogId >= 0) {
      try {
        UiBridge.uiContext?.getPromptAction().closeCustomDialog(request.dialogId);
        Log.audit(request.traceId, '关闭完成', `对话框ID=${request.dialogId}`);
      } catch (error) {
        Log.audit(request.traceId, '异常', '关闭对话框失败；未记录回调原文');
      }
      request.dialogId = -1;
    }
    if (UiBridge.active === request) {
      UiBridge.active = undefined;
    }
    const resolve = request.resolver;
    request.resolver = undefined;
    if (resolve !== undefined) {
      Log.audit(request.traceId, '响应返回', `脚本Promise结算；类型=${request.answer === null ? 'null/取消' : typeof request.answer}；队列释放`);
      resolve(request.answer);
    }
  }

  // ------------------------------------------------------------- script API

  /** `UI.showDialog`. Resolves when an action was tapped and its callback ran. */
  static async showDialog(title: string, content: string, actions: UiAction[], trace: string = ''): Promise<number> {
    const request = new UiRequest();
    request.traceId = trace;
    request.kind = 'dialog';
    request.title = title;
    request.content = content;
    request.actions = actions;
    request.dismissible = false;
    const result = await UiBridge.enqueue(request);
    return typeof result === 'number' ? result as number : -1;
  }

  /** `UI.showInputDialog`. Resolves with the text, or null when cancelled. */
  static async showInputDialog(title: string, validator: Object | undefined,
    imageUrl: string, trace: string = ''): Promise<string | null> {
    const request = new UiRequest();
    request.traceId = trace;
    request.kind = 'input';
    request.title = title;
    request.validator = validator;
    request.imageUrl = imageUrl;
    request.dismissible = false;
    const result = await UiBridge.enqueue(request);
    return typeof result === 'string' ? result as string : null;
  }

  /** `UI.showSelectDialog`. Resolves with the chosen index, or null. */
  static async showSelectDialog(title: string, options: string[],
    initialIndex: number, ownerTrace: string = ''): Promise<number | null> {
    if (options.length === 0) {
      const trace = ownerTrace || `ui-${Date.now()}-${UiBridge.nextTrace++}`;
      Log.audit(trace, '请求到达', '选择请求：选项数=0');
      Log.audit(trace, '请求被拒绝', '选项列表为空，未渲染');
      Log.audit(trace, '响应返回', '类型=null');
      return null;
    }
    const request = new UiRequest();
    request.traceId = ownerTrace;
    request.kind = 'select';
    request.title = title;
    request.options = options;
    // Upstream drops an out-of-range initial index instead of clamping.
    request.initialIndex = initialIndex >= 0 && initialIndex < options.length ? initialIndex : -1;
    request.dismissible = false;
    const result = await UiBridge.enqueue(request);
    return typeof result === 'number' ? result as number : null;
  }

  /** `UI.showLoading` returns a synchronous id, so the dialog opens detached. */
  static showLoading(onCancel: Object | undefined, trace: string = ''): number {
    let id = UiBridge.nextLoadingId;
    while (UiBridge.loading.has(id)) {
      id++;
    }
    UiBridge.nextLoadingId = id + 1;
    const request = new UiRequest();
    request.traceId = trace;
    request.kind = 'loading';
    request.title = '加载中…';
    request.id = id;
    request.onCancel = onCancel;
    request.dismissible = onCancel !== undefined;
    UiBridge.loading.set(id, request);
    UiBridge.enqueue(request).then((): void => {
      UiBridge.loading.delete(id);
    }, (): void => {
      UiBridge.loading.delete(id);
    });
    return id;
  }

  static cancelLoading(id: number): void {
    const request = UiBridge.loading.get(id);
    if (request === undefined) {
      return;
    }
    UiBridge.loading.delete(id);
    request.cancelled = true;
    Log.audit(request.traceId, '取消加载', `加载ID=${id}；位置=${UiBridge.active === request ? '活动' : '排队'}`);
    // Only the visible request can be closed; others resolve as they surface.
    if (UiBridge.active === request) {
      UiBridge.settle(null);
    }
  }

  // ------------------------------------------------------- host callbacks

  /** A dialog action was tapped; `index` is -1 when the dialog has no actions. */
  static finishDialog(index: number): void {
    UiBridge.settle(index);
  }

  /** The input dialog was confirmed with `value`. */
  static finishInput(value: string): void {
    UiBridge.settle(value);
  }

  /** The input/select dialog was cancelled. */
  static cancelAnswer(): void {
    UiBridge.settle(null);
  }

  /** The select dialog chose `index`. */
  static finishSelect(index: number): void {
    UiBridge.settle(index);
  }

  /** The loading dialog's cancel button: notify the script, then close. */
  static async cancelLoadingRequest(): Promise<void> {
    const request = UiBridge.active;
    if (request === undefined || request.settled || request.cancelCallbackRunning) {
      return;
    }
    request.cancelCallbackRunning = true;
    Log.audit(request.traceId, '用户操作', '取消加载框，准备调用脚本onCancel');
    if (request !== undefined && request.onCancel !== undefined) {
      try {
        await JsEngine.invokeFunction(request.onCancel, [], request.traceId);
        Log.audit(request.traceId, '回调完成', 'onCancel异步回调已完成');
      } catch (error) {
        Log.audit(request.traceId, '异常', 'onCancel回调失败；不记录可能含会话信息的回调原文');
      }
    }
    if (UiBridge.active === request) {
      UiBridge.settle(null);
    }
  }
}
