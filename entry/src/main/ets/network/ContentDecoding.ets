import { decodeHttpBody } from 'libvenerajs.so';
import { Log } from '../foundation/Log';

export class ContentDecoding {
  static decode(bytes: ArrayBuffer, header: string, trace: string, limit: number, sdkHandled: boolean = true): ArrayBuffer {
    const encodings = header.split(',').map((s: string) => s.trim().toLowerCase()).filter((s: string) => s.length > 0 && s !== 'identity');
    if (encodings.length === 0) { return bytes; }
    // NetStack sets CURLOPT_ACCEPT_ENCODING="" and libcurl decodes before its
    // body callback. The original server header alone is NOT proof of raw data.
    if (sdkHandled) {
      Log.audit(trace, 'HTTP编码由SDK处理', `响应头编码层数=${encodings.length}；保留SDK已返回字节，不猜测/重复解压；原生具体行为待fixture实测`);
      return bytes;
    }
    Log.audit(trace, 'HTTP解压到达', `编码层数=${encodings.length}；输入字节=${bytes.byteLength}；输出上限=${limit}；正文不落盘`);
    let result = bytes;
    try {
      // Content encodings are applied in the listed order and decoded in reverse.
      for (let i = encodings.length - 1; i >= 0; i--) {
        const encoding = encodings[i];
        if (!['gzip', 'x-gzip', 'deflate', 'br'].includes(encoding)) { throw new Error('不支持的HTTP Content-Encoding'); }
        result = decodeHttpBody(result, encoding, limit);
      }
      Log.audit(trace, 'HTTP解压返回', `输出字节=${result.byteLength}；字节响应和文本响应共用，字符集解码在后`);
      return result;
    } catch (error) {
      Log.audit(trace, 'HTTP解压拒绝/异常', '压缩数据无效/截断/超过上限/编码不支持；不把压缩原文交给JSON/HTML解析器冒充成功');
      throw new Error(error instanceof Error ? error.message : String(error));
    }
  }
}
