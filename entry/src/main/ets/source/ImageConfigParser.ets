import { isFunction } from 'libvenerajs.so';
import { ImageRequestConfig } from './ComicSource';
import { Log } from '../foundation/Log';

/** Shared initial-hook and recovery-hook normalization. No implicit fallback on malformed configs. */
export class ImageConfigParser {
  static parse(value: Object | null, fallbackUrl: string, trace: string): ImageRequestConfig {
    Log.audit(trace, '图片配置解析到达', '初始/失败恢复配置共用校验；不记录地址、正文或凭据');
    try {
      if (value === null || typeof value !== 'object' || Array.isArray(value)) { throw new Error('图片配置必须为对象'); }
      const record = value as Record<string, Object>;
      const result = new ImageRequestConfig();
      result.url = fallbackUrl;
      if (record['url'] !== undefined && record['url'] !== null) {
        if (typeof record['url'] !== 'string') { throw new Error('图片url必须为字符串'); }
        result.url = record['url'] as string;
      }
      if (result.url.length === 0) { throw new Error('图片地址为空'); }
      const headers = record['headers'];
      if (headers instanceof Map) {
        (headers as Map<string, Object>).forEach((v: Object, k: string) => { result.headers.set(k, String(v)); });
      } else if (headers !== undefined && headers !== null) {
        if (typeof headers !== 'object' || Array.isArray(headers)) { throw new Error('图片headers必须为对象'); }
        const map = headers as Record<string, Object>;
        for (const name of Object.keys(map)) {
          if (map[name] !== undefined && map[name] !== null) { result.headers.set(name, String(map[name])); }
        }
      }
      const method = record['method'];
      if (method !== undefined && method !== null) {
        if (typeof method !== 'string') { throw new Error('图片method必须为字符串'); }
        result.method = method.toUpperCase();
      }
      if (!['GET', 'POST', 'PUT', 'DELETE', 'HEAD', 'OPTIONS', 'PATCH'].includes(result.method)) {
        throw new Error('图片请求方法不支持；未转换成裸GET');
      }
      const transform = record['modifyImage'];
      if (transform !== undefined && transform !== null) {
        if (typeof transform !== 'string') { throw new Error('modifyImage必须为脚本字符串'); }
        result.modifyImage = transform;
      }
      if (record['data'] !== undefined && record['data'] !== null) { result.data = record['data']; }
      // Upstream only executes JSInvokable callbacks, ignoring nonfunctions.
      if (record['onResponse'] !== undefined && isFunction(record['onResponse'])) { result.onResponse = record['onResponse']; }
      if (record['onLoadFailed'] !== undefined && isFunction(record['onLoadFailed'])) { result.onLoadFailed = record['onLoadFailed']; }
      Log.audit(trace, '图片配置解析返回', `方法=${result.method}；头部数=${result.headers.size}；数据=${result.data !== undefined}；响应回调=${result.onResponse !== undefined}；恢复回调=${result.onLoadFailed !== undefined}；像素变换=${result.modifyImage.length > 0}`);
      return result;
    } catch (error) {
      Log.audit(trace, '图片配置解析拒绝', '配置字段无效；未进入网络请求');
      throw new Error(error instanceof Error ? error.message : String(error));
    }
  }
}
