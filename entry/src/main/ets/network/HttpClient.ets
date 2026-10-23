import { http } from '@kit.NetworkKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { Log } from '../foundation/Log';
import { CookieJar } from './CookieJar';
import { ContentDecoding } from './ContentDecoding';

/**
 * HTTP response wrapper.
 *
 * Dart original: VeneraNext used Dio (`network/app_dio.dart`) with a `rhttp`
 * adapter for HTTP/2, proxies and DNS overrides. HarmonyOS has no rhttp
 * equivalent, so requests go through @ohos.net.http; proxy/TLS knobs are not
 * exposed here yet.
 */
export class HttpResponse {
  status: number = 0;
  headers: Map<string, string> = new Map<string, string>();
  body: string = '';
  bytes?: ArrayBuffer;

  get ok(): boolean {
    return this.status >= 200 && this.status < 300;
  }
}

export class HttpRequestOptions {
  traceId: string = '';
  headers: Map<string, string> = new Map<string, string>();
  /** Send a JSON body and set Content-Type accordingly. */
  jsonBody?: string;
  /** Plain string body without guessing JSON/form Content-Type. */
  rawBody?: string;
  formBody?: string;
  /** Raw request payload (scripts POST binary uploads through `http`). */
  extraData?: Uint8Array;
  connectTimeoutMs: number = 20000;
  readTimeoutMs: number = 60000;
  /** Return raw bytes instead of a decoded string. */
  asBytes: boolean = false;
  /** Retry attempts on transport failure (timeouts are common on mobile). */
  retries: number = 1;
  maxDecodedBytes: number = 64 * 1024 * 1024;
  /** NetStack normally returns decoded bytes. Explicit false is for a proven raw-body transport/test, never header guessing. */
  sdkHandlesContentEncoding: boolean = true;
  /** Explicit public diagnostics only: neither send nor persist Cookie jar state. */
  useCookieJar: boolean = true;
}

/**
 * Turn a thrown value into readable text.
 *
 * @ohos.net.http rejects with a BusinessError that is not an `Error` instance,
 * so `String(error)` produced "[object Object]" and every network failure looked
 * the same in the logs.
 */
export function describeError(error: Object): string {
  if (error instanceof Error) {
    return error.message;
  }
  const record = error as Record<string, Object>;
  const message = record['message'];
  const code = record['code'];
  if (message !== undefined) {
    return code !== undefined ? `code ${code}: ${message}` : String(message);
  }
  try {
    const json = JSON.stringify(error);
    return json === undefined ? String(error) : json;
  } catch (inner) {
    return String(error);
  }
}

export function headersToRecord(headers: Map<string, string>): Record<string, string> {
  const record: Record<string, string> = {};
  for (const key of headers.keys()) {
    record[key] = headers.get(key) as string;
  }
  return record;
}

export function recordToHeaders(record: Object | undefined): Map<string, string> {
  const headers = new Map<string, string>();
  if (record === undefined || record === null) {
    return headers;
  }
  const map = record as Record<string, Object>;
  for (const key of Object.keys(map)) {
    const value = map[key];
    if (value !== undefined && value !== null) {
      headers.set(key, String(value));
    }
  }
  return headers;
}

const USER_AGENT: string =
  'Mozilla/5.0 (Phone; OpenHarmony 6.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36';

/**
 * Thin HTTP facade. One HttpRequest object per call; HarmonyOS requires the
 * request object to be destroyed explicitly.
 */
export class HttpClient {
  /** Webview and default HTTP requests share UA so imported session cookies aren't tied to a different UA. */
  static defaultUserAgent(): string { return USER_AGENT; }
  private static hasHeader(headers: Map<string, string>, name: string): boolean {
    for (const key of headers.keys()) { if (key.toLowerCase() === name.toLowerCase()) { return true; } }
    return false;
  }
  private static headerValue(headers: Map<string, string>, name: string): string {
    for (const key of headers.keys()) { if (key.toLowerCase() === name.toLowerCase()) { return headers.get(key) ?? ''; } }
    return '';
  }
  static async request(url: string, method: http.RequestMethod,
                       options: HttpRequestOptions): Promise<HttpResponse> {
    if (options.traceId.length === 0) { options.traceId = `http-${Date.now()}-${Math.floor(Math.random() * 1000000)}`; }
    const trace = options.traceId;
    Log.audit(trace, 'HTTP请求到达', `方法=${method}；头部数=${options.headers.size}；二进制响应=${options.asBytes}；URL/头部/请求正文不落盘`);
    let lastError: Object = new Error('request failed');
    const attempts = options.retries + 1;
    for (let attempt = 0; attempt < attempts; attempt++) {
      try {
        Log.audit(trace, 'HTTP尝试', `次数=${attempt + 1}/${attempts}；连接超时=${options.connectTimeoutMs}ms；读取超时=${options.readTimeoutMs}ms`);
        const response = await HttpClient.attempt(url, method, options);
        Log.audit(trace, 'HTTP响应返回', `状态=${response.status}；二进制字节=${response.bytes?.byteLength ?? 0}；文本长度=${response.body.length}；正文不落盘`);
        return response;
      } catch (error) {
        lastError = error;
        const message = describeError(error).replace(/https?:\/\/\S+/g, '[URL]');
        Log.audit(trace, 'HTTP尝试异常', `方法=${method}；次数=${attempt + 1}/${attempts}；原因=${message}`);
        if (attempt + 1 < attempts) {
          await new Promise<void>((resolve: () => void) => {
            setTimeout(() => {
              resolve();
            }, 400 * (attempt + 1));
          });
        }
      }
    }
    const message = describeError(lastError).replace(/https?:\/\/\S+/g, '[URL]');
    Log.audit(trace, 'HTTP异常返回', `方法=${method}；所有尝试结束；原因=${message}`);
    throw new Error(`网络请求失败: ${message}`);
  }

  private static async attempt(url: string, method: http.RequestMethod,
                               options: HttpRequestOptions): Promise<HttpResponse> {
    const request = http.createHttp();
    try {
      // Never mutate caller-owned headers (the same options can be retried).
      const headers = new Map<string, string>(options.headers);
      const jarHeader = options.useCookieJar ? CookieJar.header(url) : '';
      if (jarHeader.length > 0) {
        let existing = '';
        for (const key of headers.keys()) {
          if (key.toLowerCase() === 'cookie') {
            existing = headers.get(key) ?? '';
            headers.delete(key);
          }
        }
        headers.set('Cookie', existing.length > 0 ? `${existing}; ${jarHeader}` : jarHeader);
      }
      Log.audit(options.traceId, 'HTTP会话头处理', `附加Cookie=${jarHeader.length > 0}；头部数=${headers.size}；不记录会话秘密`);
      if (!HttpClient.hasHeader(headers, 'User-Agent')) {
        headers.set('User-Agent', USER_AGENT);
      }
      // Prefer identity when the source does not request compression. NetStack
      // enables libcurl decoding; ARRAY_BUFFER and Content-Encoding headers do
      // not imply that its returned body is still compressed.
      if (!HttpClient.hasHeader(headers, 'Accept-Encoding')) {
        headers.set('Accept-Encoding', 'identity');
      }
      if (options.jsonBody !== undefined && !HttpClient.hasHeader(headers, 'Content-Type')) {
        headers.set('Content-Type', 'application/json');
      }
      if (options.formBody !== undefined && !HttpClient.hasHeader(headers, 'Content-Type')) {
        headers.set('Content-Type', 'application/x-www-form-urlencoded');
      }

      const requestOptions: http.HttpRequestOptions = {
        method: method,
        header: headersToRecord(headers),
        connectTimeout: options.connectTimeoutMs,
        readTimeout: options.readTimeoutMs,
        // Always take the raw bytes: decoding is done here so the charset and
        // any residual compression are under our control.
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        usingCache: false
      };
      if (options.rawBody !== undefined) {
        if (options.rawBody.length > 0) { requestOptions.extraData = options.rawBody; }
      } else if (options.jsonBody !== undefined) {
        if (options.jsonBody.length > 0) { requestOptions.extraData = options.jsonBody; }
      } else if (options.formBody !== undefined) {
        if (options.formBody.length > 0) { requestOptions.extraData = options.formBody; }
      } else if (options.extraData !== undefined && options.extraData.byteLength > 0) {
          const exact = new ArrayBuffer(options.extraData.byteLength);
          new Uint8Array(exact).set(options.extraData);
          requestOptions.extraData = exact;
      }
      Log.audit(options.traceId, 'HTTP正文适配', `带正文=${requestOptions.extraData !== undefined}；空正文不传SDK extraData；二进制子视图精确复制`);

      const response = await request.request(url, requestOptions);
      // Preserve the raw Set-Cookie shape before recordToHeaders flattens
      // string[] values; even a 401 response can establish login cookies.
      if (options.useCookieJar) { CookieJar.receive(url, response.header); }
      const result = new HttpResponse();
      result.status = response.responseCode;
      result.headers = recordToHeaders(response.header);

      let bytes: ArrayBuffer | undefined = undefined;
      if (response.result instanceof ArrayBuffer) {
        bytes = response.result as ArrayBuffer;
      } else if (typeof response.result === 'string') {
        // Copy into a plain ArrayBuffer: Uint8Array.buffer is ArrayBufferLike,
        // which ArkTS refuses to treat structurally as ArrayBuffer.
        const encoded = new util.TextEncoder().encodeInto(response.result as string);
        const copy = new ArrayBuffer(encoded.length);
        new Uint8Array(copy).set(encoded);
        bytes = copy;
      }

      const encoding = HttpClient.headerValue(result.headers, 'content-encoding').toLowerCase();
      if (bytes !== undefined && encoding.length > 0) {
        bytes = ContentDecoding.decode(bytes, encoding, options.traceId, options.maxDecodedBytes, options.sdkHandlesContentEncoding);
      }

      if (options.asBytes) {
        result.bytes = bytes;
        result.body = '';
      } else if (bytes === undefined) {
        result.body = '';
      } else {
        result.body = HttpClient.decodeBody(bytes, result.headers);
      }
      return result;
    } catch (error) {
      // The retry loop above owns logging; rethrow so it can decide.
      throw error instanceof Error ? error : new Error(describeError(error));
    } finally {
      request.destroy();
    }
  }

  /** Decode a body using the charset advertised in Content-Type (default utf-8). */
  private static decodeBody(bytes: ArrayBuffer, headers: Map<string, string>): string {
    const contentType = HttpClient.headerValue(headers, 'content-type').toLowerCase();
    let charset = 'utf-8';
    const match = /charset=([a-z0-9_\-]+)/.exec(contentType);
    if (match !== null) {
      const declared = match[1];
      if (declared === 'gbk' || declared === 'gb2312' || declared === 'gb18030') {
        charset = 'gb18030';
      } else if (declared === 'big5') {
        charset = 'big5';
      }
    }
    try {
      const decoder = util.TextDecoder.create(charset);
      return decoder.decodeToString(new Uint8Array(bytes));
    } catch (error) {
      Log.warn('HttpClient', `cannot decode with ${charset}: ${error}`);
      const decoder = util.TextDecoder.create('utf-8');
      return decoder.decodeToString(new Uint8Array(bytes));
    }
  }

  static async getText(url: string, headers?: Map<string, string>): Promise<HttpResponse> {
    const options = new HttpRequestOptions();
    if (headers !== undefined) {
      options.headers = headers;
    }
    return HttpClient.request(url, http.RequestMethod.GET, options);
  }

  static async getBytes(url: string, headers?: Map<string, string>, trace: string = ''): Promise<HttpResponse> {
    const options = new HttpRequestOptions();
    options.traceId = trace;
    if (headers !== undefined) {
      options.headers = headers;
    }
    options.asBytes = true;
    return HttpClient.request(url, http.RequestMethod.GET, options);
  }

  static async postForm(url: string, form: string,
                        headers?: Map<string, string>): Promise<HttpResponse> {
    const options = new HttpRequestOptions();
    if (headers !== undefined) {
      options.headers = headers;
    }
    options.formBody = form;
    return HttpClient.request(url, http.RequestMethod.POST, options);
  }

  static async postJson(url: string, json: string,
                        headers?: Map<string, string>): Promise<HttpResponse> {
    const options = new HttpRequestOptions();
    if (headers !== undefined) {
      options.headers = headers;
    }
    options.jsonBody = json;
    return HttpClient.request(url, http.RequestMethod.POST, options);
  }

  /** GET a JSON document and parse it. Throws when the body is not valid JSON. */
  static async getJson(url: string, headers?: Map<string, string>): Promise<Object> {
    const response = await HttpClient.getText(url, headers);
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`);
    }
    try {
      return JSON.parse(response.body) as Object;
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      throw new Error(`返回内容不是合法 JSON: ${message}`);
    }
  }

  /** Download to a file path inside the app sandbox. */
  static async downloadToFile(url: string, destPath: string,
                              headers?: Map<string, string>): Promise<number> {
    const response = await HttpClient.getBytes(url, headers);
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`);
    }
    const bytes = response.bytes;
    if (bytes === undefined) {
      throw new Error('响应为空');
    }
    const fd = fs.openSync(destPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(fd.fd, bytes);
    } finally {
      fs.closeSync(fd);
    }
    return bytes.byteLength;
  }
}
