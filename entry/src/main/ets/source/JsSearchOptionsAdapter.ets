import { JsEngine } from './JsEngine';
import { SearchOptions } from './ComicSource';
import { Res } from '../model/Res';
import { Log } from '../foundation/Log';

/** Materialize the fixed upstream search.optionList, not a site's page response. */
export class JsSearchOptionsAdapter {
  static async load(sourceKey: string, scriptPath: string): Promise<Res<SearchOptions[]>> {
    const trace = `search-options-${Date.now()}`;
    try {
      const value = await JsEngine.callJson(`(()=>{const search=ComicSource.sources[${JSON.stringify(sourceKey)}]?.search;` +
        'if(!search)throw Error("SEARCH_CAPABILITY_MISSING");return search.optionList??[];})()', scriptPath, trace);
      if (!Array.isArray(value)) { throw new Error('搜索 optionList 必须是数组'); }
      const groups: SearchOptions[] = [];
      for (const raw of value as Object[]) {
        if (raw === null || typeof raw !== 'object' || Array.isArray(raw)) { throw new Error('搜索筛选组必须是对象'); }
        const record = raw as Record<string, Object>;
        const group = new SearchOptions();
        if (record['label'] !== undefined && typeof record['label'] !== 'string') { throw new Error('筛选标题必须是字符串'); }
        group.label = typeof record['label'] === 'string' ? record['label'] as string : '';
        group.type = typeof record['type'] === 'string' ? record['type'] as string : 'select';
        if (!['select', 'multi-select', 'dropdown'].includes(group.type)) { throw new Error('源声明的筛选类型暂不支持'); }
        const rawOptions = record['options'];
        if (!Array.isArray(rawOptions)) { throw new Error('搜索筛选 options 必须是数组'); }
        for (const option of rawOptions as Object[]) {
          if (typeof option !== 'string') { throw new Error('搜索筛选项必须是字符串'); }
          const split = option.indexOf('-');
          if (split < 0) { continue; }
          // Empty first key is a valid "no filter" value; label keeps later dashes.
          group.options.set(option.slice(0, split), option.slice(split + 1));
        }
        if (record['default'] !== undefined && record['default'] !== null) {
          group.defaultVal = JSON.stringify(record['default']);
        }
        groups.push(group);
      }
      Log.audit(trace, '搜索筛选元数据返回', `源=${sourceKey}；组数=${groups.length}；选项/默认值内容不落盘`);
      return Res.ok<SearchOptions[]>(groups);
    } catch (error) {
      Log.audit(trace, '搜索筛选元数据异常', '声明无效或桥接失败；不回显源异常/参数正文');
      return Res.fail<SearchOptions[]>('搜索筛选配置加载失败，请刷新；不会使用其他源的选项');
    }
  }
}
