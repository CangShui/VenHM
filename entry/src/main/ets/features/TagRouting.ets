import { router } from '@kit.ArkUI';
import { ComicDetails } from '../model/ComicDetails';
import { CategoryComicsParams } from '../model/RouteParams';
import { CategoryItem, ComicSource } from '../source/ComicSource';
import { Log } from '../foundation/Log';

export class DetailTag {
  namespace: string = '';
  value: string = '';
  get label(): string { return this.namespace.length > 0 ? `${this.namespace}:${this.value}` : this.value; }
}

/** Keep the namespace/value separate: splitting flattened strings loses colon-containing tags. */
export class TagRouting {
  static tags(details?: ComicDetails): DetailTag[] {
    const result: DetailTag[] = [];
    if (details !== undefined) {
      for (const namespace of details.tags.keys()) {
        for (const value of details.tags.get(namespace) ?? []) {
          const tag = new DetailTag(); tag.namespace = namespace; tag.value = value; result.push(tag);
        }
      }
    }
    return result;
  }

  static params(sourceKey: string, item: CategoryItem): CategoryComicsParams {
    if (item.page === 'category') {
      const category = item.attributes.get('category');
      if (category === undefined || category.length === 0) { throw new Error('分类目标缺少 category 参数'); }
      return { sourceKey: sourceKey, label: item.label, page: 'category', category: category,
        param: item.attributes.get('param'), options: item.initialOptions.slice() };
    }
    if (item.page === 'search') {
      const keyword = item.attributes.get('text') ?? item.attributes.get('keyword');
      if (keyword === undefined || (keyword.length === 0 && item.initialOptions.length === 0)) {
        throw new Error('搜索目标缺少 text/keyword 或筛选选项');
      }
      return { sourceKey: sourceKey, label: item.label, page: 'search', keyword: keyword,
        options: item.initialOptions.slice() };
    }
    throw new Error(`暂不支持源提供的 ${item.page} 目标`);
  }

  static async resolve(source: ComicSource, tag: DetailTag): Promise<CategoryItem> {
    if (source.tagTarget !== undefined) {
      const target = await source.tagTarget(tag.namespace, tag.value);
      if (target === undefined) { throw new Error('源未提供该标签的跳转目标'); }
      target.label = target.label || tag.label;
      return target;
    }
    // Upstream fallback is a namespaced search, NEVER infer a category name from a tag.
    if (!source.supportsSearch) { throw new Error('选中的源不支持标签搜索且未提供标签目标'); }
    const target = new CategoryItem(); target.label = tag.label; target.page = 'search';
    target.attributes.set('keyword', tag.label); return target;
  }

  static async open(sourceKey: string, target: CategoryItem, trace: string): Promise<void> {
    const params = TagRouting.params(sourceKey, target);
    Log.audit(trace, '标签分类路由到达', `目标类型=${params.page}；保留原始源；参数内容不落盘`);
    await router.pushUrl({ url: 'pages/CategoryComicsPage', params: params });
    Log.audit(trace, '标签分类路由返回', '已打开源锁定结果页');
  }
}
