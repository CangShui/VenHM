import { util } from '@kit.ArkTS';
import { decodeHttpBody } from 'libvenerajs.so';
import { Log } from '../foundation/Log';

/** Independent Node-generated vectors test the packaged NAPI codec, not a real website. */
export class NativeHttpCodecUsability {
  static run(): void {
    const trace = `native-http-codec-${Date.now()}`;
    const base64 = new util.Base64Helper();
    const vectors: string[][] = [
      ['gzip', 'H4sIAAAAAAAACqtWyk0tLk5MT1WyUnq5dsqzzVMVPsyf0aCko1ScX1qUDBIurswryUgtyUxWqgUAX1EF6y4AAAA='],
      ['deflate', 'eJyrVspNLS5OTE9VslJ6uXbKs81TFT7Mn9GgpKNUnF9alAwSLq7MK8lILclMVqoFAM91Exk='],
      ['deflate', 'q1bKTS0uTkxPVbJSerl2yrPNUxU+zJ/RoKSjVJxfWpQMEi6uzCvJSC3JTFaqBQA='],
      ['br', 'ixaAeyJtZXNzYWdlIjoi6a2U5rOVIPCfmIAiLCJzb3VyY2UiOiJzeW50aGV0aWMifQM=']
    ];
    const expected = base64.decodeSync('eyJtZXNzYWdlIjoi6a2U5rOVIPCfmIAiLCJzb3VyY2UiOiJzeW50aGV0aWMifQ==');
    Log.audit(trace, '原生解码契约到达', 'gzip/zlib/raw-deflate/br固定向量；无外网/真实账号');
    for (const vector of vectors) {
      const input = base64.decodeSync(vector[1]);
      const exact = new ArrayBuffer(input.byteLength);
      new Uint8Array(exact).set(input);
      const actual = new Uint8Array(decodeHttpBody(exact, vector[0], 1024));
      if (actual.byteLength !== expected.byteLength || actual.some((v: number, i: number) => v !== expected[i])) {
        throw new Error('原生HTTP解码固定向量不符');
      }
      Log.audit(trace, '原生解码契约返回', `编码=${vector[0]}；输出字节=${actual.length}；逐字节符合预期`);
      let rejected = false;
      try { decodeHttpBody(exact, vector[0], 1); } catch (error) { rejected = true; }
      if (!rejected) { throw new Error('原生HTTP解码上限未拒绝'); }
    }
    Log.info('NativeHttpCodecUsability', 'PASS · packaged native gzip/zlib/raw-deflate/Brotli vectors and limits (not SDK transport)');
  }
}
