import { SearchOptions } from '../source/ComicSource';

/** Pure positional search-option policy shared by the search panel and tests. */
export class SearchFilterPolicy {
  static defaults(groups: SearchOptions[]): string[] {
    const result: string[] = [];
    for (const group of groups) {
      if (!['select', 'multi-select', 'dropdown'].includes(group.type)) { throw new Error('暂不支持该源的搜索筛选类型'); }
      let declared: Object | null = null;
      if (group.defaultVal !== undefined) {
        try { declared = JSON.parse(group.defaultVal) as Object | null; }
        catch (error) { throw new Error('搜索筛选默认值不是有效JSON'); }
      }
      if (group.type === 'multi-select') {
        const values: string[] = [];
        if (declared !== null) {
          if (!Array.isArray(declared)) { throw new Error('多选筛选默认值必须是数组'); }
          for (const value of declared as Object[]) {
            if (typeof value !== 'string' || !group.options.has(value)) { throw new Error('多选默认值含无效选项'); }
            if (!values.includes(value)) { values.push(value); }
          }
        }
        result.push(JSON.stringify(values));
      } else {
        const keys = Array.from(group.options.keys());
        if (keys.length === 0) { throw new Error('搜索筛选没有可选项'); }
        let value: string = keys[0];
        if (declared !== null) {
          if (typeof declared !== 'string' && typeof declared !== 'number' && typeof declared !== 'boolean') {
            throw new Error('单选筛选默认值必须是简单值');
          }
          value = String(declared);
        }
        if (!group.options.has(value)) { throw new Error('搜索筛选默认值不在选项中'); }
        result.push(value);
      }
    }
    return result;
  }

  static selected(group: SearchOptions, value: string, key: string): boolean {
    if (group.type !== 'multi-select') { return value === key; }
    return SearchFilterPolicy.multiValues(group, value).includes(key);
  }

  private static multiValues(group: SearchOptions, value: string): string[] {
    let parsed: Object;
    try { parsed = JSON.parse(value) as Object; }
    catch (error) { throw new Error('多选筛选格式无效，请重置筛选'); }
    if (!Array.isArray(parsed) || !(parsed as Object[]).every((key: Object) =>
      typeof key === 'string' && group.options.has(key))) { throw new Error('多选筛选含无效值，请重置'); }
    const result: string[] = [];
    for (const key of parsed as string[]) { if (!result.includes(key)) { result.push(key); } }
    return result;
  }

  static change(groups: SearchOptions[], current: string[], index: number, key: string): string[] {
    const values = SearchFilterPolicy.validate(groups, current);
    const group = groups[index];
    if (group === undefined || !group.options.has(key)) { throw new Error('选中的搜索筛选项无效'); }
    if (group.type === 'multi-select') {
      const selected = SearchFilterPolicy.multiValues(group, values[index]);
      const at = selected.indexOf(key);
      if (at < 0) { selected.push(key); } else { selected.splice(at, 1); }
      values[index] = JSON.stringify(selected);
    } else { values[index] = key; }
    return values;
  }

  static validate(groups: SearchOptions[], values: string[]): string[] {
    if (groups.length !== values.length) { throw new Error('搜索筛选项数量已变化，请刷新筛选'); }
    const result = values.slice();
    for (let index = 0; index < groups.length; index++) {
      const group = groups[index];
      if (group.type === 'multi-select') { result[index] = JSON.stringify(SearchFilterPolicy.multiValues(group, values[index])); }
      else if (!group.options.has(values[index])) { throw new Error('搜索筛选项已失效，请刷新'); }
    }
    return result;
  }
}
