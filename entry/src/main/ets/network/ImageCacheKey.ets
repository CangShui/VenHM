import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';

/** Cache varies by URL + request headers + session cookie; secrets never form filenames. */
export function imageCacheKey(url: string, headers: Map<string, string>, cookie: string, transform: string = ''): string {
  const values: string[] = [];
  headers.forEach((value: string, key: string) => { values.push(`${key.toLowerCase()}:${value}`); });
  values.sort();
  const md = cryptoFramework.createMd('SHA256');
  md.updateSync({ data: new util.TextEncoder().encodeInto(JSON.stringify([url, values, cookie, transform])) });
  let result = '';
  for (const byte of md.digestSync().data) { result += byte.toString(16).padStart(2, '0'); }
  return result;
}
