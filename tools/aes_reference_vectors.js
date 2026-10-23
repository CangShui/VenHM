/* Reference AES vectors for the JS <-> ArkTS convert bridge.
 * Run: node tools/aes_reference_vectors.js
 * ECB/CBC use raw NoPadding blocks; CFB8 and OFB use a zero IV.
 */
'use strict';
const { createCipheriv } = require('node:crypto');
const key = Buffer.alloc(16);
const iv = Buffer.alloc(16);
const plain = Buffer.from(Array.from({ length: 16 }, (_, i) => i));
for (const mode of ['ecb', 'cbc', 'cfb8', 'ofb']) {
  const cipher = createCipheriv(`aes-128-${mode}`, key, mode === 'ecb' ? null : iv);
  cipher.setAutoPadding(false);
  const bytes = Buffer.concat([cipher.update(plain), cipher.final()]);
  console.log(`${mode}: ${bytes.toString('hex')}`);
}
// The unpadded zero block is the NIST SP 800-38A AES-128 ECB vector.
const zero = createCipheriv('aes-128-ecb', key, null);
zero.setAutoPadding(false);
console.log(`zero-ecb: ${Buffer.concat([zero.update(Buffer.alloc(16)), zero.final()]).toString('hex')}`);
