import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { wantAgent } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppContext } from '../foundation/AppContext';
import { Log } from '../foundation/Log';

/** Owns one real DATA_TRANSFER continuous task. Never started by restoration/lifecycle. */
export class BackgroundDownloadCoordinator {
  private static owner: string = '';
  private static epoch: number = 0;
  private static acceptedEpoch: number = -1;
  private static nativeId: number = -1;
  private static pending: Promise<void> | undefined = undefined;
  private static stopPending: Promise<void> | undefined = undefined;
  private static cancelledRegistered: boolean = false;
  private static suspendedRegistered: boolean = false;
  private static failure: (message: string) => void = (_message: string): void => {};
  static error: string = '';

  private static cancelled = (info: backgroundTaskManager.ContinuousTaskCancelInfo): void => {
    if (BackgroundDownloadCoordinator.owner.length > 0 && BackgroundDownloadCoordinator.nativeId >= 0 &&
      info.id === BackgroundDownloadCoordinator.nativeId) {
      BackgroundDownloadCoordinator.lost(`系统取消后台数据传输（原因=${info.reason}）`);
    }
  };
  private static suspended = (info: backgroundTaskManager.ContinuousTaskSuspendInfo): void => {
    if (info.suspendState && BackgroundDownloadCoordinator.owner.length > 0 && BackgroundDownloadCoordinator.nativeId >= 0 &&
      info.continuousTaskId === BackgroundDownloadCoordinator.nativeId) {
      BackgroundDownloadCoordinator.lost(`系统挂起后台数据传输（原因=${info.suspendReason}）`);
    }
  };

  private static describe(error: Object): string {
    const code = (error as BusinessError).code;
    const message = error instanceof Error ? error.message : String(error);
    // This code is verification failure, not proof of a duplicate/stale task.
    if (code === 9800005) {
      return '系统拒绝后台数据传输（校验失败 9800005）；后台未获许可，仅可在前台下载';
    }
    return `后台数据传输服务失败${code === undefined ? '' : `（代码=${code}）`}：${message}`;
  }

  private static lost(message: string): void {
    BackgroundDownloadCoordinator.error = message;
    BackgroundDownloadCoordinator.epoch++;
    BackgroundDownloadCoordinator.failure(message);
    // Keep nativeId until stop resolves; even a suspended service must be released.
    BackgroundDownloadCoordinator.stop().catch((error: Object) => {
      Log.audit('downloads-background', '后台服务停止失败', `phase=native-stop；code=${(error as BusinessError).code}`);
    });
  }

  static held(id: string): boolean {
    return BackgroundDownloadCoordinator.owner === id && BackgroundDownloadCoordinator.nativeId >= 0 &&
      BackgroundDownloadCoordinator.error.length === 0 && BackgroundDownloadCoordinator.acceptedEpoch === BackgroundDownloadCoordinator.epoch;
  }

  /** Only called by explicit user resume, before the first network request. */
  static async start(id: string, onFailure: (message: string) => void): Promise<void> {
    if (BackgroundDownloadCoordinator.stopPending !== undefined) { await BackgroundDownloadCoordinator.stopPending; }
    if (BackgroundDownloadCoordinator.owner.length > 0 || BackgroundDownloadCoordinator.pending !== undefined ||
      BackgroundDownloadCoordinator.nativeId >= 0) {
      await BackgroundDownloadCoordinator.stop();
    }
    BackgroundDownloadCoordinator.error = '';
    BackgroundDownloadCoordinator.owner = id;
    BackgroundDownloadCoordinator.failure = onFailure;
    const epoch = ++BackgroundDownloadCoordinator.epoch;
    const request = BackgroundDownloadCoordinator.startNative(epoch);
    BackgroundDownloadCoordinator.pending = request;
    try { await request; }
    finally { if (BackgroundDownloadCoordinator.pending === request) { BackgroundDownloadCoordinator.pending = undefined; } }
    if (!BackgroundDownloadCoordinator.held(id) || BackgroundDownloadCoordinator.epoch !== epoch) {
      throw new Error(BackgroundDownloadCoordinator.error || '后台数据传输启动已取消');
    }
  }

  private static async startNative(epoch: number): Promise<void> {
    let phase = 'listeners';
    try {
      backgroundTaskManager.on('continuousTaskCancel', BackgroundDownloadCoordinator.cancelled);
      BackgroundDownloadCoordinator.cancelledRegistered = true;
      backgroundTaskManager.on('continuousTaskSuspend', BackgroundDownloadCoordinator.suspended);
      BackgroundDownloadCoordinator.suspendedRegistered = true;
      phase = 'want-agent';
      Log.audit('downloads-background', '后台申请阶段', phase);
      const agent = await wantAgent.getWantAgent({
        wants: [{ bundleName: AppContext.bundleName, abilityName: 'EntryAbility',
          parameters: { openDownloads: true } }],
        operationType: wantAgent.OperationType.START_ABILITY,
        requestCode: 8041,
        wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      });
      if (epoch !== BackgroundDownloadCoordinator.epoch) { return; }
      const request = new backgroundTaskManager.ContinuousTaskRequest();
      request.backgroundTaskModes = [backgroundTaskManager.BackgroundTaskMode.MODE_DATA_TRANSFER];
      // API21 requires a matching subtype, not an empty/default subtype.
      // Published mapping: DATA_TRANSFER -> LIVE_VIEW_NOTIFICATION (not NORMAL).
      // https://github.com/openharmony/docs/blob/master/en/application-dev/reference/apis-backgroundtasks-kit/js-apis-resourceschedule-backgroundTaskManager.md#backgroundtasksubmode21
      request.backgroundTaskSubmodes = [backgroundTaskManager.BackgroundTaskSubmode.SUBMODE_LIVE_VIEW_NOTIFICATION];
      request.wantAgent = agent;
      phase = 'is-mode-supported';
      Log.audit('downloads-background', '后台申请阶段', phase);
      if (!request.isModeSupported()) { throw new Error('设备不支持 DATA_TRANSFER 后台模式'); }
      phase = 'native-start';
      Log.audit('downloads-background', '后台申请阶段', phase);
      const notification = await backgroundTaskManager.startBackgroundRunning(AppContext.context, request);
      if (notification.continuousTaskId === undefined || !Number.isSafeInteger(notification.continuousTaskId) ||
        notification.continuousTaskId < 0) {
        // No known owned ID: never stop all tasks belonging to this UIAbility.
        throw new Error('系统未返回有效后台任务标识；未停止其他后台任务');
      }
      // Record even a late acceptance: stopNative awaits pending and releases this
      // exact ID after epoch invalidation. Never drop an accepted native lease.
      BackgroundDownloadCoordinator.nativeId = notification.continuousTaskId;
      BackgroundDownloadCoordinator.acceptedEpoch = epoch;
      Log.audit('downloads-background', '后台申请阶段', epoch === BackgroundDownloadCoordinator.epoch ? 'accepted' : 'accepted-after-cancel');
    } catch (error) {
      const code = (error as BusinessError).code;
      Log.audit('downloads-background', '后台申请失败', `phase=${phase}；code=${code === undefined ? 'none' : code}`);
      BackgroundDownloadCoordinator.error = BackgroundDownloadCoordinator.describe(error as Object);
      if (BackgroundDownloadCoordinator.nativeId < 0) {
        BackgroundDownloadCoordinator.releaseListeners();
        BackgroundDownloadCoordinator.owner = '';
      }
      throw new Error(BackgroundDownloadCoordinator.error);
    }
  }

  private static releaseListeners(): void {
    if (BackgroundDownloadCoordinator.cancelledRegistered) {
      try { backgroundTaskManager.off('continuousTaskCancel', BackgroundDownloadCoordinator.cancelled); }
      catch (error) { Log.audit('downloads-background', '监听释放失败', `phase=cancel-off；code=${(error as BusinessError).code}`); }
      BackgroundDownloadCoordinator.cancelledRegistered = false;
    }
    if (BackgroundDownloadCoordinator.suspendedRegistered) {
      try { backgroundTaskManager.off('continuousTaskSuspend', BackgroundDownloadCoordinator.suspended); }
      catch (error) { Log.audit('downloads-background', '监听释放失败', `phase=suspend-off；code=${(error as BusinessError).code}`); }
      BackgroundDownloadCoordinator.suspendedRegistered = false;
    }
  }

  /** Invalidates immediately; waits for an in-flight native start before releasing it. */
  static stop(): Promise<void> {
    if (BackgroundDownloadCoordinator.stopPending !== undefined) { return BackgroundDownloadCoordinator.stopPending; }
    BackgroundDownloadCoordinator.epoch++;
    const request = BackgroundDownloadCoordinator.stopNative();
    BackgroundDownloadCoordinator.stopPending = request;
    request.then(() => {
      if (BackgroundDownloadCoordinator.stopPending === request) { BackgroundDownloadCoordinator.stopPending = undefined; }
    }, () => {
      if (BackgroundDownloadCoordinator.stopPending === request) { BackgroundDownloadCoordinator.stopPending = undefined; }
    });
    return request;
  }

  private static async stopNative(): Promise<void> {
    const pending = BackgroundDownloadCoordinator.pending;
    if (pending !== undefined) { try { await pending; } catch (_) {} }
    try {
      if (BackgroundDownloadCoordinator.nativeId >= 0) {
        await backgroundTaskManager.stopBackgroundRunning(AppContext.context, BackgroundDownloadCoordinator.nativeId);
        BackgroundDownloadCoordinator.nativeId = -1;
      }
    } catch (error) {
      Log.audit('downloads-background', '后台停止失败', `phase=native-stop；code=${(error as BusinessError).code}`);
      BackgroundDownloadCoordinator.error = BackgroundDownloadCoordinator.describe(error as Object);
      // Preserve nativeId/owner so a later explicit retry can release it, not create a duplicate.
      throw new Error(BackgroundDownloadCoordinator.error);
    } finally {
      BackgroundDownloadCoordinator.releaseListeners();
      if (BackgroundDownloadCoordinator.nativeId < 0) { BackgroundDownloadCoordinator.owner = ''; }
    }
  }
}
