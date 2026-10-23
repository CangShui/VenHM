import { image } from '@kit.ImageKit';
import { http } from '@kit.NetworkKit';
import { JsEngine } from '../source/JsEngine';
import { ImageConfigParser } from '../source/ImageConfigParser';
import { ImagePipeline } from '../network/ImagePipeline';
import { HttpClient, HttpRequestOptions } from '../network/HttpClient';
import { Log } from '../foundation/Log';

/** Explicit CLI-only local HTTP fixture; never sends reading data or account credentials. */
export class ImagePipelineUsability {
  static async run(): Promise<string[]> {
    const trace = `image-http-probe-${Date.now()}`;
    const base = 'http://127.0.0.1:29091';
    const options = new HttpRequestOptions();
    options.traceId = trace; options.retries = 0; options.connectTimeoutMs = 3000; options.readTimeoutMs = 3000;
    const health = await HttpClient.request(`${base}/health`, http.RequestMethod.GET, options);
    if (!health.ok || health.body !== '{"fixture":"venera-hm-image-v1"}') {
      throw new Error('没有检测到CLI专用图片测试服务器，未执行POST；不要向未知地址上传数据');
    }
    Log.audit(trace, '图片HTTP验收到达', '确认本机fixture身份；仅发送固定合成数据，无用户账号/历史/收藏');
    for (const codec of ['gzip', 'deflate', 'br']) {
      const compressed = new HttpRequestOptions();
      compressed.traceId = trace; compressed.retries = 0;
      compressed.headers.set('Accept-Encoding', codec);
      const response = await HttpClient.request(`${base}/encoding/${codec}`, http.RequestMethod.GET, compressed);
      if (!response.ok || response.body !== '{"message":"synthetic compressed response","ok":true}') {
        throw new Error(`SDK ${codec}字节/字符集路径未通过，不归因于源规则`);
      }
      Log.audit(trace, 'SDK压缩实测比对', `编码=${codec}；实际HTTP返回JSON与独立服务器预期逐字符相符`);
    }
    await ImagePipelineUsability.case(
      `({url:${JSON.stringify(`${base}/post`)},method:"POST",data:"a=1",headers:{"Content-Type":"application/x-www-form-urlencoded"}})`,
      2, 3, trace);
    await ImagePipelineUsability.case(
      `({url:${JSON.stringify(`${base}/empty`)},method:"POST",data:""})`, 2, 3, trace);
    await ImagePipelineUsability.case(
      `({url:${JSON.stringify(`${base}/binary`)},method:"POST",data:new Uint8Array([9,1,2,8]).subarray(1,3)})`, 2, 3, trace);
    await ImagePipelineUsability.case(
      `({url:${JSON.stringify(`${base}/encrypted`)},onResponse:async bytes=>bytes.subarray(1),` +
      `modifyImage:"let modifyImage = image => image.copyAndRotate90();"})`, 3, 2, trace);
    await ImagePipelineUsability.case(
      `({url:${JSON.stringify(`${base}/failure`)},onLoadFailed:async ()=>({url:${JSON.stringify(`${base}/image`)}})})`,
      2, 3, trace);
    const bad: Object | null = await JsEngine.callJson(`(()=>{let recover=()=>({url:${JSON.stringify(`${base}/always-fail`)},` +
      `onLoadFailed:recover});return {url:${JSON.stringify(`${base}/always-fail`)},onLoadFailed:recover}})()`, '<image-http-limit>');
    let rejected = false;
    try { await ImagePipeline.fetch(ImageConfigParser.parse(bad, `${base}/always-fail`, trace), trace); }
    catch (error) { rejected = true; }
    if (!rejected) { throw new Error('失败恢复上限没有拒绝'); }
    Log.audit(trace, '图片HTTP验收返回', 'PASS · POST正文/空正文/二进制子视图、真实QuickJS异步onResponse→旋转、onLoadFailed换配置、上限拒绝；仍非真实站点账号验收');
    return ['PASS · 本机真实HTTP图片配置/空POST/子视图/异步响应处理/像素旋转/失败恢复已通过',
      'PASS · 恢复上限已拒绝；需主机fixture日志复核always-fail恰好6次；没有用户数据上传'];
  }

  private static async case(code: string, width: number, height: number, trace: string): Promise<void> {
    const value: Object | null = await JsEngine.callJson(code, '<image-http-fixture>');
    const config = ImageConfigParser.parse(value, 'http://127.0.0.1:29091/image', trace);
    const bytes = await ImagePipeline.fetch(config, trace);
    const decoder = image.createImageSource(bytes);
    try {
      const pixel = await decoder.createPixelMap();
      try {
        const info = await pixel.getImageInfo();
        if (info.size.width !== width || info.size.height !== height) { throw new Error('测试图片处理尺寸不符合预期'); }
      } finally { await pixel.release(); }
    } finally { await decoder.release(); }
    Log.audit(trace, '图片HTTP用例比对', `预期/实际尺寸=${width}x${height}；方法=${config.method}；回调输入内容不落盘`);
  }
}
