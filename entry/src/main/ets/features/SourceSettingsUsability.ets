import { Settings } from '../foundation/Settings';
import { Log } from '../foundation/Log';
import { Database } from '../storage/Database';
import { JsEngine } from '../source/JsEngine';
import { ComicSource } from '../source/ComicSource';
import { SourceManager } from '../source/SourceManager';
import { SourceDataStore } from '../source/SourceDataStore';

/** Opt-in isolated fixture; never edits settings or credentials of real sources. */
export class SourceSettingsUsability {
  static readonly key: string = '__HM_SETTINGS_USABILITY__';
  private static readonly flag: string = 'sourceSettingsUsabilityEnabled';
  private static readonly owner: string = 'hm-settings-fixture-v1';

  private static register(): void {
    const key = JSON.stringify(SourceSettingsUsability.key);
    JsEngine.evaluate('(() => { const key=' + key + ';' +
      ' const source=new ComicSource();source.key=key;source.name="离线源设置样本";' +
      ' Object.defineProperty(source,"settings",{get(){ const s=source;' +
      ' const data=s.loadData("settings")||{};const count=s.loadData("callback_count")||0;' +
      ' return {' +
      ' input:{type:"input",title:"离线校验（请输入42）",default:"",required:"42",' +
      '  validator:async function(v){await Promise.resolve();return v===this.required?null:"必须输入42";}},' +
      ' mode:{type:"switch",title:"动态开关",default:false},' +
      ' choice:{type:"select",title:"动态选项",default:0,get options(){return [' +
      '  {value:0,text:"数值零"},{value:false,text:"布尔false"},' +
      '  data.mode?{value:2,text:"动态二"}:{value:1,text:"动态一"}];}},' +
      ' callback:{type:"callback",title:"回调计数："+count,buttonText:"执行无副作用回调",marker:"receiver",' +
      '  callback:async function(){if(this.marker!=="receiver")throw Error("callback this lost");' +
      '   await Promise.resolve();s.saveData("callback_count",count+1);}}' +
      ' };}});ComicSource.sources[key]=source; })()', '<settings-fixture>');
    if (SourceManager.find(SourceSettingsUsability.key) === undefined) {
      SourceManager.register(new ComicSource(SourceSettingsUsability.key, '离线源设置样本'));
    }
  }

  static async prepare(): Promise<string> {
    const trace = `settings-fixture-${Date.now()}`;
    await SourceDataStore.preload(SourceSettingsUsability.key);
    const existing = SourceDataStore.get(SourceSettingsUsability.key, '_owner');
    if (existing !== null && existing !== SourceSettingsUsability.owner) {
      throw new Error('拒绝覆盖非本验收创建的源数据');
    }
    if (SourceManager.find(SourceSettingsUsability.key) !== undefined &&
        existing !== SourceSettingsUsability.owner) {
      throw new Error('验收源key与既有源冲突');
    }
    await SourceDataStore.setAndWait(SourceSettingsUsability.key, '_owner', SourceSettingsUsability.owner, trace);
    await Settings.setBool(SourceSettingsUsability.flag, true);
    SourceSettingsUsability.register();
    Log.audit(trace, '样本就绪', '只注册离线设置样本；不安装源脚本，不使用账号、不联网');
    return SourceSettingsUsability.key;
  }

  static async restoreIfEnabled(): Promise<void> {
    if (!Settings.getBool(SourceSettingsUsability.flag, false)) {
      return;
    }
    await SourceDataStore.preload(SourceSettingsUsability.key);
    if (SourceDataStore.get(SourceSettingsUsability.key, '_owner') !== SourceSettingsUsability.owner) {
      throw new Error('离线设置样本所有权标记不匹配');
    }
    if (SourceManager.find(SourceSettingsUsability.key) !== undefined) {
      throw new Error('离线设置样本与已安装源冲突');
    }
    SourceSettingsUsability.register();
    Log.audit('settings-fixture-restore', '重启恢复', '离线源设置样本已恢复，可检查跨进程保存；未修改实际源');
  }

  static async cleanup(): Promise<void> {
    const trace = `settings-fixture-cleanup-${Date.now()}`;
    await SourceDataStore.preload(SourceSettingsUsability.key);
    const owner = SourceDataStore.get(SourceSettingsUsability.key, '_owner');
    if (owner === null) {
      await Settings.remove(SourceSettingsUsability.flag);
      return;
    }
    if (owner !== SourceSettingsUsability.owner) {
      throw new Error('拒绝删除无本验收所有权标记的数据');
    }
    // Awaited barrier drains preceding JS saveData writes before the scoped delete.
    await SourceDataStore.setAndWait(SourceSettingsUsability.key, '_cleanup', true, trace);
    await Settings.remove(SourceSettingsUsability.flag);
    await Database.execute('DELETE FROM source_data WHERE source_key = ?', [SourceSettingsUsability.key]);
    for (const key of ['settings', 'callback_count', '_owner', '_cleanup']) {
      SourceDataStore.remove(SourceSettingsUsability.key, key);
    }
    SourceManager.unregister(SourceSettingsUsability.key);
    JsEngine.evaluate(`delete ComicSource.sources[${JSON.stringify(SourceSettingsUsability.key)}]`, '<settings-fixture-cleanup>');
    const rows = await Database.query('SELECT COUNT(*) FROM source_data WHERE source_key = ?', [SourceSettingsUsability.key]);
    try {
      if (!rows.goToFirstRow() || rows.getLong(0) !== 0) {
        throw new Error('离线设置样本数据库清理未完成');
      }
    } finally {
      rows.close();
    }
    Log.audit(trace, '清理完成', '只删除带所有权标记的离线源设置样本，真实源/账号/收藏/历史不变');
  }
}
