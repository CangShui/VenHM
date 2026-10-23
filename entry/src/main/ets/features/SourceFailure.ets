/** Safe UI diagnostics: retain error kind/code, never raw response/credentials. */
export class SourceFailure {
  static message(error: Object | undefined | null): string {
    let text: string = '';
    if (error instanceof Error) { text = error.message; }
    else if (typeof error === 'string') { text = error; }
    else if (error !== undefined && error !== null && typeof error === 'object') {
      const record = error as Record<string, Object>;
      if (typeof record['message'] === 'string') { text = record['message'] as string; }
      if (typeof record['code'] === 'number') { text = `SDK code ${record['code']} ${text}`; }
    }
    if (/setting not found/i.test(text)) { return '源缺少必需设置，请在源设置中检查；未更改已保存的账号或数据'; }
    if (/not logged|need login|未登录/i.test(text)) { return '该源提示需要登录，请在设备上自行登录后重试'; }
    // Extract ONLY fixed technical observations, not an arbitrary error string
    // that may contain HTML, authorization headers, account or response body.
    const status = text.match(/(?:http|status(?: code)?|状态码)[\s:=]+([1-5]\d\d)\b/i);
    if (status !== null) { return `源请求返回 HTTP ${status[1]}，请重试；原因尚需请求/源规则对照`; }
    const code = text.match(/\bcode\s*[:=]?\s*(\d{1,12})\b/i);
    if (code !== null) { return `请求/SDK 错误码 ${code[1]}；这不是HTTP状态码，请检查网络后重试`; }
    const kind = text.match(/\b(TypeError|SyntaxError|ReferenceError|RangeError)\b/);
    if (kind !== null) { return `源脚本 ${kind[1]}，未得到可用列表；已记录失败阶段，请重试`; }
    if (/timeout|timed out|超时/i.test(text)) { return '源请求超时，请检查网络或稍后重试'; }
    if (/decode|解码/i.test(text)) { return '源图片无法解码，请重试；不将错误页当作漫画图片'; }
    return '源未返回可用结果，请重试；诊断记录保留具体阶段';
  }
}
