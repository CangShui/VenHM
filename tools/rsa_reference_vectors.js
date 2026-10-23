/* Reference RSA vector for the JS <-> ArkTS convert bridge (`Convert.decryptRsa`).
 *
 * Run: node tools/rsa_reference_vectors.js            # verify the embedded vector
 *      node tools/rsa_reference_vectors.js --generate # print a fresh vector
 *
 * The same three constants are embedded in entry/src/main/ets/source/JsEngine.ets
 * (offline L0 contract check) so a device run reports
 *   `RSA-1024 PKCS1 decrypt vector OK`
 * without needing any source script that uses RSA.
 *
 * Semantics mirrored from the Dart original (venera lib/foundation/js_engine.dart):
 * base64 PKCS#8 PrivateKeyInfo -> PKCS#1 RSAPrivateKey -> PKCS1 (v1.5) decrypt,
 * processed in modulus-sized blocks.
 */
'use strict';
const { generateKeyPairSync, publicEncrypt, privateDecrypt, constants, createPrivateKey } = require('node:crypto');

// --- embedded vector (1024-bit, generated once) ------------------------------
const VECTOR = {
  pkcs8: 'MIICdgIBADANBgkqhkiG9w0BAQEFAASCAmAwggJcAgEAAoGBAMfvZcwn+3wtqpriKBsosBv8Ycl/6Z1Ea5USlaNWF1r3WvrUXbgll5OnBgj8W7nBVLwAm/0BLDU8VinAucucze1wFSPrcWhe0yN63vG7v1Vm7214pG4lJ6gC0B9e1EwlJQXyLbx1NlRDtwFNdQfIoZJMpkWOfZRzENKQ2yoS6rWNAgMBAAECgYBVowXgT1PZmZnUo3/4OhJMumqMK1y9/vtxq7cqcgqo7QAsJeBKqtdk6AqeuLD1PIj1yfEGioUL/F8PnTw3qV9OTUTO7JLNCST3G/H/2AqqxqhP+vyRtlaAb9WxMO9Io+cOO5WN1x8fuAQ44elSAxrHCrrMiSUtK3zk2O98cJ4MoQJBAO2Mr1D+yqEkgtkVipErp/SLcrF/D/W1oS80K+n7gUNBV8L0whJQhfsAbLuQblqORnDR4F1TYaMZo5KevzxX0PkCQQDXds6aOzn7DtRHIGE6n3iTqJTfDYpxucYOIRukMTGmpCkFe8a3hR6urB716pUjzA04QnV6+4oABFAbwOfHDoI1AkAPmb2pxBHqo0s0loWTIxrUpJPTtFSH/nWnc/WuWCYVFKV+2DQmn8MsyMpbRxD4QX++yQnDF0bCP1zOtD466EmBAkBO00AyXIiRuJMgkk//ymeqXXpZP/LuODCk6qfaIcUwWc5IG0hPy3u2G3IYNYHqXrRXaLjiDTQnXWyROrmQsVYhAkEArn/khbCs7ShDS7flw7wSVEGdxZs3aNc6BEhDDtpcreChNFLs8eCGLBDyEEk8WDyCsw4q2qQcHOOTFlCO+x/2yA==',
  ciphertext: 'pCYmePLCUzGGJkUwajglGiYQioc989Sw7cCLvloi7KEoF+9v95Xh1P1P9VvsE+yRPcA4GGIrKtfl1xmN68W54LL59EjKN67FK5KNYhGoaO4WIXC4EzGX8BtZGJZJbE13J1nDCC27pfFPD7BWs/LuS6gj5ploQRtNrWSZqAOnJ7s=',
  plaintext: '{"code":0,"data":{"key":"venera-rsa-vector"}}'
};

function generate() {
  const { privateKey, publicKey } = generateKeyPairSync('rsa', { modulusLength: 1024 });
  const der = privateKey.export({ type: 'pkcs8', format: 'der' });
  const plaintext = '{"code":0,"data":{"key":"venera-rsa-vector"}}';
  const ciphertext = publicEncrypt(
    { key: publicKey, padding: constants.RSA_PKCS1_PADDING },
    Buffer.from(plaintext, 'utf8'));
  console.log('pkcs8:      ' + der.toString('base64'));
  console.log('ciphertext: ' + ciphertext.toString('base64'));
  console.log('plaintext:  ' + plaintext);
  console.log(`(modulus ${ciphertext.length} bytes, plaintext ${Buffer.byteLength(plaintext)} bytes)`);
}

function verify() {
  if (VECTOR.pkcs8 === 'REPLACE_ME') {
    console.error('no embedded vector yet - run with --generate');
    process.exit(2);
  }
  const key = createPrivateKey({ key: Buffer.from(VECTOR.pkcs8, 'base64'), format: 'der', type: 'pkcs8' });
  const decrypted = privateDecrypt(
    { key, padding: constants.RSA_PKCS1_PADDING },
    Buffer.from(VECTOR.ciphertext, 'base64'));
  const text = decrypted.toString('utf8');
  const cipherBytes = Buffer.from(VECTOR.ciphertext, 'base64').length;
  if (text !== VECTOR.plaintext) {
    console.error(`FAIL vector plaintext mismatch: ${text}`);
    process.exit(1);
  }
  if (cipherBytes % 128 !== 0) {
    console.error(`FAIL ciphertext is not a whole number of 128-byte blocks: ${cipherBytes}`);
    process.exit(1);
  }
  console.log(`PASS rsa vector: ${cipherBytes} byte block -> ${text}`);
}

if (process.argv.includes('--generate')) {
  generate();
} else {
  verify();
}
