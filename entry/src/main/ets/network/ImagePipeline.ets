import { image } from '@kit.ImageKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { invokeFunction } from 'libvenerajs.so';
import { http } from '@kit.NetworkKit';
import { ImageRequestConfig } from '../source/ComicSource';
import { ImageConfigParser } from '../source/ImageConfigParser';
import { AppContext } from '../foundation/AppContext';
import { Log } from '../foundation/Log';
import { HttpClient, HttpRequestOptions } from './HttpClient';
import { ImageTransforms } from './ImageTransforms';

/** One byte pipeline for covers/reader/download/acceptance, with upstream's five recovery attempts. */
export class ImagePipeline {
  static requestOptions(config: ImageRequestConfig, trace: string): HttpRequestOptions {
    const options = new HttpRequestOptions();
    options.traceId = trace;
    options.headers = config.headers;
    options.asBytes = true;
    // Avoid replaying a non-idempotent POST/PUT on an ambiguous transport failure.
    options.retries = 0;
    const data = config.data;
    if (data instanceof Uint8Array) { options.extraData = data; }
    else if (data instanceof ArrayBuffer) { options.extraData = new Uint8Array(data); }
    else if (typeof data === 'string') { options.rawBody = data; }
    else if (data !== undefined && data !== null) { options.jsonBody = JSON.stringify(data); }
    return options;
  }

  private static method(value: string): http.RequestMethod {
    switch (value) {
      case 'GET': return http.RequestMethod.GET;
      case 'POST': return http.RequestMethod.POST;
      case 'PUT': return http.RequestMethod.PUT;
      case 'DELETE': return http.RequestMethod.DELETE;
      case 'HEAD': return http.RequestMethod.HEAD;
      case 'OPTIONS': return http.RequestMethod.OPTIONS;
      // Older SDKs omit the enum member; NetStack consumes the wire string.
      // Preserve PATCH exactly, never replace it with GET or undefined.
      case 'PATCH': return 'PATCH' as http.RequestMethod;
      default: throw new Error('未知图片请求方法');
    }
  }

  private static local(url: string): ArrayBuffer {
    const path = url.substring(7);
    if (!path.startsWith(`${AppContext.localComicDir}/`) || path.split('/').includes('..') ||
      path.includes('\\') || !fs.statSync(path).isFile()) { throw new Error('图片桥拒绝读取本地漫画目录外或非普通文件'); }
    const bytes = new ArrayBuffer(fs.statSync(path).size);
    const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
    try {
      if (fs.readSync(file.fd, bytes) !== bytes.byteLength) { throw new Error('本地图片读取不完整'); }
      return bytes;
    } finally { fs.closeSync(file); }
  }

  private static bytes(value: Object | null): ArrayBuffer {
    let array: Uint8Array;
    if (value instanceof Uint8Array) { array = value; }
    else if (value instanceof ArrayBuffer) { array = new Uint8Array(value); }
    else if (Array.isArray(value) && (value as Object[]).every((v: Object) =>
      typeof v === 'number' && Number.isSafeInteger(v))) {
      // Dart Uint8List.fromList wraps integer values modulo 256.
      array = new Uint8Array(value as number[]);
    }
    else { throw new Error('onResponse必须返回字节数组'); }
    const result = new ArrayBuffer(array.byteLength);
    new Uint8Array(result).set(array);
    return result;
  }

  static async fetch(initial: ImageRequestConfig, trace: string,
    shouldContinue: () => boolean = (): boolean => true): Promise<ArrayBuffer> {
    let config = initial;
    const fallback = initial.url;
    Log.audit(trace, '图片流水线到达', '配置→请求→onResponse→modifyImage→实际解码；最多5次配置恢复');
    for (let attempt = 0; attempt <= 5; attempt++) {
      if (!shouldContinue()) {
        Log.audit(trace, '图片流水线拒绝', `尝试=${attempt + 1}；页面/任务已取消，未进入请求`);
        throw new Error('IMAGE_REQUEST_CANCELLED');
      }
      try {
        if (config.unsupported.length > 0) { throw new Error('IMAGE_CONFIG_UNSUPPORTED'); }
        let bytes: ArrayBuffer;
        if (config.url.startsWith('file://')) {
          if (config.method !== 'GET' || config.data !== undefined) { throw new Error('本地图片不支持请求方法/正文'); }
          bytes = ImagePipeline.local(config.url);
        } else {
          if (!/^https?:\/\//.test(config.url)) { throw new Error('图片网络地址必须为HTTP(S)'); }
          const response = await HttpClient.request(config.url, ImagePipeline.method(config.method),
            ImagePipeline.requestOptions(config, trace));
          if (!response.ok || response.bytes === undefined) { throw new Error(`图片HTTP ${response.status}`); }
          bytes = response.bytes;
        }
        if (!shouldContinue()) { throw new Error('IMAGE_REQUEST_CANCELLED'); }
        if (config.onResponse !== undefined) {
          Log.audit(trace, '图片响应回调到达', `输入字节=${bytes.byteLength}；等待同步/异步回调`);
          bytes = ImagePipeline.bytes(await invokeFunction(config.onResponse, [new Uint8Array(bytes)], trace));
          Log.audit(trace, '图片响应回调返回', `输出字节=${bytes.byteLength}；不记录字节内容`);
        }
        if (!shouldContinue()) { throw new Error('IMAGE_REQUEST_CANCELLED'); }
        bytes = await ImageTransforms.apply(bytes, config.modifyImage, trace, shouldContinue);
        if (!shouldContinue()) { throw new Error('IMAGE_REQUEST_CANCELLED'); }
        const decoder = image.createImageSource(bytes);
        try {
          const pixel = await decoder.createPixelMap();
          try {
            const info = await pixel.getImageInfo();
            if (info.size.width <= 0 || info.size.height <= 0) { throw new Error('图片尺寸无效'); }
            Log.audit(trace, '图片流水线返回', `尝试=${attempt + 1}；实际解码=${info.size.width}x${info.size.height}；字节=${bytes.byteLength}`);
          } finally { await pixel.release(); }
        } finally { await decoder.release(); }
        return bytes;
      } catch (error) {
        if (!shouldContinue()) {
          Log.audit(trace, '图片流水线取消', '页面/任务取消，未调用失败恢复或开启下一请求');
          throw new Error('IMAGE_REQUEST_CANCELLED');
        }
        const handler = config.onLoadFailed;
        if (handler === undefined || attempt === 5) {
          Log.audit(trace, '图片流水线异常返回', `尝试=${attempt + 1}；恢复回调=${handler !== undefined}；不返回原始乱序/无效图片`);
          throw new Error(error instanceof Error ? error.message : String(error));
        }
        Log.audit(trace, '图片失败恢复到达', `已用恢复次数=${attempt}；准备调用onLoadFailed，不重复使用旧请求配置`);
        let value: Object | null;
        try { value = await invokeFunction(handler, [], trace); }
        catch (recoveryError) {
          Log.audit(trace, '图片失败恢复异常', '回调抛错/Promise拒绝；不继续联网，不输出回调内容');
          throw new Error('onLoadFailed回调执行失败');
        }
        if (value === null || typeof value !== 'object' || Array.isArray(value)) {
          Log.audit(trace, '图片失败恢复拒绝', '回调未返回配置对象；终止，不发裸GET');
          throw new Error(error instanceof Error ? error.message : String(error));
        }
        config = ImageConfigParser.parse(value, fallback, trace);
        Log.audit(trace, '图片失败恢复返回', `新方法=${config.method}；剩余恢复次数=${4 - attempt}`);
      }
    }
    throw new Error('图片恢复次数用尽');
  }
}
