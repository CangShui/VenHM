import { ComicSource, ImageRequestConfig } from './ComicSource';
import { Log } from '../foundation/Log';

/** Shared by covers, reader pages, download queue and source acceptance. */
export class ImageRequests {
  static async resolve(source: ComicSource | undefined, url: string, thumbnail: boolean,
    comicId: string, epId: string, trace: string): Promise<ImageRequestConfig> {
    const raw = new ImageRequestConfig();
    raw.url = url;
    Log.audit(trace, '图片配置', `缩略图=${thumbnail}；源=${source?.key ?? 'none'}；URL/头部内容不落盘`);
    let config: ImageRequestConfig;
    if (thumbnail) {
      config = source?.getThumbnailConfig !== undefined ? await source.getThumbnailConfig(url, trace) : raw;
    } else if (source?.getImageConfig !== undefined) {
      config = await source.getImageConfig(url, comicId, epId, trace);
    } else {
      config = raw;
    }
    if (config.unsupported.length > 0) {
      Log.audit(trace, '应用缺口', `图片请求需要尚未实现的功能：${config.unsupported.join(',')}`);
      throw new Error(`IMAGE_CONFIG_UNSUPPORTED: ${config.unsupported.join(',')}`);
    }
    if (config.url.length === 0) {
      config.url = url;
    }
    Log.audit(trace, '图片配置完成', `头部数=${config.headers.size}；地址改写=${config.url !== url}；像素变换=${config.modifyImage.length > 0}`);
    return config;
  }
}
