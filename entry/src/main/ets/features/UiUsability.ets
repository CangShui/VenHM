import { JsEngine } from '../source/JsEngine';
import { Log } from '../foundation/Log';

/**
 * Interactive end-to-end test of the `UI.*` bridge.
 *
 * It runs a real source-style script that awaits dialogs, so the verdict also
 * depends on the person tapping. That is deliberate: the point is to prove the
 * ArkTS dialog -> JS callback -> JS promise chain, which no offline assertion
 * can cover. The script never touches user data or the network.
 */
export class UiUsability {
  private static readonly script: string =
    '(async () => {' +
    ' const out = [];' +
    // The validator is a JS callback: it must be invoked from ArkTS, see the
    // error string surface in the dialog, and finally let the dialog close.
    ' const input = await UI.showInputDialog("UI 自检：请输入 42",' +
    ' (v) => (v === "42" ? null : "必须输入 42"), null);' +
    ' out.push("input=" + input);' +
    ' const idx = await UI.showSelectDialog("UI 自检：请选择一项", ["甲", "乙", "丙"], 1);' +
    ' out.push("select=" + idx);' +
    // Action callbacks must run (and be awaited) before the dialog closes.
    ' let tapped = -1;' +
    // Upstream UI.showDialog intentionally returns void (init.js unchanged).
    // Await the callback's signal, not the void API return.
    ' await new Promise(done => UI.showDialog("UI 自检：确认对话框", "按钮回调会写回脚本", [' +
    ' { text: "取消", style: "text", callback: () => { tapped = 0; done(); } },' +
    ' { text: "确定", style: "filled", callback: async () => {' +
    '   await Promise.resolve(); tapped = 1; done(); } }]));' +
    ' out.push("dialog=" + tapped);' +
    ' const id = UI.showLoading(null);' +
    ' UI.cancelLoading(id);' +
    ' out.push("queuedLoadingCancelled=true");' +
    ' const visibleId = UI.showLoading(null);' +
    ' await new Promise(r => setTimeout(r, 150));' +
    ' UI.cancelLoading(visibleId);' +
    ' UI.showDialog("UI 自检：加载框已关闭", "只应出现此对话框，没有残留加载框", []);' +
    ' out.push("visibleLoadingCancelled=true");' +
    ' const cancelledInput = await UI.showInputDialog("UI 自检：请取消输入", null, null);' +
    ' const cancelledSelect = await UI.showSelectDialog("UI 自检：请取消选择", ["甲", "乙"], 99);' +
    ' out.push("cancelInput=" + cancelledInput + " | cancelSelect=" + cancelledSelect);' +
    ' let onCancelCount=0, signal; const cancelled = new Promise(r => { signal=r; });' +
    ' UI.showLoading(async () => { await Promise.resolve(); onCancelCount++; signal(); });' +
    ' await cancelled;' +
    ' await new Promise(done => UI.showDialog("UI 自检：取消回调完成", "加载框取消后队列应正常继续",' +
    ' [{text:"确定",callback:()=>done()}]));' +
    ' out.push("onCancel=" + onCancelCount);' +
    ' if(input !== "42" || idx !== 2 || tapped !== 1 || cancelledInput !== null || ' +
    ' cancelledSelect !== null || onCancelCount !== 1) throw new Error("UI自检结果不符合预期：" + out.join(" | "));' +
    ' UI.showMessage("UI 自检完成");' +
    ' return "PASS | " + out.join(" | ");' +
    '})()';

  static async run(): Promise<string> {
    const trace = `ui-self-test-${Date.now()}`;
    if (!JsEngine.isAvailable) {
      Log.audit(trace, '请求被拒绝', 'QuickJS未初始化，未执行自检');
      throw new Error('QuickJS 尚未初始化');
    }
    Log.audit(trace, '请求到达', '执行输入42/选择丙/异步按钮/两种加载取消/输入和选择取消/onCancel；不联网不写用户数据');
    try {
      const result: Object | null = await JsEngine.callJson(UiUsability.script, '<ui-self-test>');
      const text = typeof result === 'string' ? result as string : String(result);
      if (!Log.isTracePersisted(trace)) {
        throw new Error('UI审计日志未在应用logs目录读回');
      }
      const report = `${text} | auditFile=true`;
      Log.info('UiUsability', report);
      Log.audit(trace, '响应返回', report);
      return report;
    } catch (error) {
      Log.audit(trace, '异常', `UI自检失败：${error}`);
      throw new Error(error instanceof Error ? error.message : String(error));
    }
  }
}
