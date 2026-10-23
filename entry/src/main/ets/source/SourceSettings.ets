import { JsEngine } from './JsEngine';
import { SourceDataStore } from './SourceDataStore';
import { Log } from '../foundation/Log';

export class SourceSettingOption {
  value: string | number | boolean = '';
  text: string = '';
}

export class SourceSettingField {
  key: string = '';
  title: string = '';
  type: string = '';
  defaultValue?: Object;
  validatorKind: string = 'none';
  buttonText: string = '点击';
  hasCallback: boolean = false;
  options: SourceSettingOption[] = [];
  schemaError: string = '';
}

/**
 * v1.17.0 comic_source_page.dart:780-873: reread settings getters after edits,
 * retain primitive option values and persist only user edits. Function-valued
 * options/validators are explicit HM compatibility extensions, not upstream
 * requirements (upstream input validators are regex strings).
 */
export class SourceSettings {
  static settingsOf(sourceKey: string): Record<string, Object> {
    const stored = SourceDataStore.get(sourceKey, 'settings');
    return stored !== null && !Array.isArray(stored) && typeof stored === 'object'
      ? stored as Record<string, Object> : {};
  }

  private static instance(sourceKey: string): string {
    return `ComicSource.sources[${JSON.stringify(sourceKey)}]`;
  }

  private static field(sourceKey: string, key: string): string {
    return `${SourceSettings.instance(sourceKey)}.settings[${JSON.stringify(key)}]`;
  }

  static async read(sourceKey: string, trace: string): Promise<SourceSettingField[]> {
    Log.audit(trace, '源设置读取', `源=${sourceKey}；重新求值settings和options，不缓存getter结果`);
    const script = '(async () => { const source = ' + SourceSettings.instance(sourceKey) + ';' +
      ' if (!source) throw new Error("Source not loaded");' +
      ' const settings = source.settings;' +
      ' if (!settings || typeof settings !== "object" || Array.isArray(settings)) return [];' +
      ' const fields = [];' +
      ' for (const key of Object.keys(settings)) {' +
      '  const base = {key, title:key, type:"unsupported", options:[], validatorKind:"none"};' +
      '  try {' +
      '   const item=settings[key]; if(!item || typeof item!=="object") continue;' +
      '   const rawOptions=item.options;' +
      '   const choices=typeof rawOptions==="function" ? await rawOptions.call(item) : await rawOptions;' +
      '   const kind=typeof item.validator;' +
      '   const options=Array.isArray(choices) ? choices.map(o => {' +
      '    if(!o || !["string","number","boolean"].includes(typeof o.value) || ' +
      '       (typeof o.value==="number" && !Number.isFinite(o.value))) throw new Error("Invalid option value");' +
      '    return {value:o.value,text:typeof o.text==="string"?o.text:String(o.value)};' +
      '   }) : [];' +
      '   if(item.type==="select" && !Array.isArray(choices)) throw new Error("Select options must be an array");' +
      '   fields.push({...base,title:typeof item.title==="string"?item.title:key,' +
      '    type:typeof item.type==="string"?item.type:"unsupported",' +
      '    defaultValue:item.default===undefined?null:item.default,' +
      '    validatorKind:item.validator==null?"none":(kind==="string"||kind==="function"?kind:"unsupported"),' +
      '    buttonText:typeof item.buttonText==="string"?item.buttonText:"点击",' +
      '    hasCallback:typeof item.callback==="function",options});' +
      '  } catch(error) { fields.push({...base,schemaError:String(error)}); }' +
      ' } return fields; })()';
    try {
      const raw = await JsEngine.callJson(script, '<source-settings-read>', trace);
      const fields: SourceSettingField[] = [];
      if (!Array.isArray(raw)) {
        throw new Error('源设置必须返回字段数组');
      }
      for (const value of raw as Object[]) {
        const record = value as Record<string, Object>;
        if (typeof record['key'] !== 'string') {
          continue;
        }
        const field = new SourceSettingField();
        field.key = record['key'] as string;
        field.title = typeof record['title'] === 'string' ? record['title'] as string : field.key;
        field.type = typeof record['type'] === 'string' ? record['type'] as string : 'unsupported';
        field.validatorKind = typeof record['validatorKind'] === 'string'
          ? record['validatorKind'] as string : 'none';
        const fallback = record['defaultValue'];
        if (fallback !== null && fallback !== undefined) {
          field.defaultValue = fallback;
        }
        field.hasCallback = record['hasCallback'] === true;
        field.buttonText = typeof record['buttonText'] === 'string' ? record['buttonText'] as string : '点击';
        field.schemaError = typeof record['schemaError'] === 'string' ? record['schemaError'] as string : '';
        const options = record['options'];
        if (Array.isArray(options)) {
          for (const rawOption of options as Object[]) {
            const choice = rawOption as Record<string, Object>;
            const primitive = choice['value'];
            if (typeof primitive === 'string' || typeof primitive === 'number' || typeof primitive === 'boolean') {
              const option = new SourceSettingOption();
              option.value = primitive as string | number | boolean;
              option.text = typeof choice['text'] === 'string' ? choice['text'] as string : String(primitive);
              field.options.push(option);
            }
          }
        }
        fields.push(field);
        Log.audit(trace, '字段读取', `键=${field.key}；类型=${field.type}；选项数=${field.options.length}；校验器=${field.validatorKind}；异常=${field.schemaError.length > 0}`);
      }
      Log.audit(trace, '源设置返回', `字段数=${fields.length}；未记录设置值`);
      return fields;
    } catch (error) {
      Log.audit(trace, '源设置异常', 'getter读取失败，具体错误显示在页面，不把设置内容写入日志');
      throw new Error(error instanceof Error ? error.message : String(error));
    }
  }

  static effective(field: SourceSettingField, saved: Record<string, Object>): Object | undefined {
    const value = saved[field.key];
    return value !== undefined && value !== null ? value : field.defaultValue;
  }

  static selectedIndex(field: SourceSettingField, saved: Record<string, Object>): number {
    const value = SourceSettings.effective(field, saved);
    return field.options.findIndex((option: SourceSettingOption) => option.value === value);
  }

  static async validate(sourceKey: string, key: string, value: string, trace: string): Promise<string> {
    Log.audit(trace, '输入校验', `源=${sourceKey}；键=${key}；长度=${value.length}；内容不落盘`);
    const script = '(async () => { const item=' + SourceSettings.field(sourceKey, key) + ';' +
      ' if(!item) throw new Error("Setting disappeared"); const rule=item.validator;' +
      ' if(rule==null) return null;' +
      ' if(typeof rule==="string") return new RegExp(rule).test(' + JSON.stringify(value) + ') ? null : "输入格式不正确";' +
      ' if(typeof rule!=="function") throw new Error("Unsupported validator type");' +
      ' const result=await rule.call(item,' + JSON.stringify(value) + ');' +
      ' if(result==null || result==="") return null;' +
      ' if(typeof result!=="string") throw new Error("Validator must return an error string or null");' +
      ' return result; })()';
    try {
      const result = await JsEngine.callJson(script, '<source-setting-validator>', trace);
      const error = result === null ? '' : String(result);
      Log.audit(trace, error.length === 0 ? '校验通过' : '校验拒绝',
        error.length === 0 ? '允许持久化' : '保留草稿，未写入设置');
      return error;
    } catch (error) {
      Log.audit(trace, '校验异常', '脚本校验失败，当前输入未保存；错误中的用户内容不落盘');
      throw new Error(error instanceof Error ? error.message : String(error));
    }
  }

  static async commit(sourceKey: string, key: string, value: Object, trace: string): Promise<void> {
    Log.audit(trace, '保存请求', `源=${sourceKey}；键=${key}；值类型=${typeof value}；内容不落盘`);
    const next: Record<string, Object> = {};
    const old = SourceSettings.settingsOf(sourceKey);
    for (const name of Object.keys(old)) {
      next[name] = old[name];
    }
    next[key] = value;
    await SourceDataStore.setAndWait(sourceKey, 'settings', next, trace);
    Log.audit(trace, '保存完成', '数据库已落盘，可以显示已保存');
  }

  static async runCallback(sourceKey: string, key: string, trace: string): Promise<void> {
    Log.audit(trace, '回调请求', `源=${sourceKey}；键=${key}；保留JS接收者this并等待Promise`);
    const target = SourceSettings.field(sourceKey, key);
    await JsEngine.callJson(`(() => { const item=${target}; if(!item || typeof item.callback!=="function") ` +
      'throw new Error("Invalid setting callback"); return item.callback(); })()', '<source-setting-callback>', trace);
    Log.audit(trace, '回调完成', '脚本回调已完成，页面须重新读取settings getter');
  }
}
