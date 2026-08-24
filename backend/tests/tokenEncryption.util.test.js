process.env.NODE_ENV = 'test';
process.env.DB_USER = 'test';
process.env.DB_NAME = 'tride_test';
process.env.JWT_ACCESS_SECRET = 'test-access-secret';
process.env.JWT_REFRESH_SECRET = 'test-refresh-secret-value';
process.env.SOCIAL_TOKEN_ENCRYPTION_KEY = Buffer.alloc(32, 7).toString('base64');

const test = require('node:test');
const assert = require('node:assert/strict');

const {
  encrypt,
  decrypt,
  resolveEncryptionKey,
  TokenEncryptionError,
} = require('../src/utils/tokenEncryption.util');

test('encrypt produces base64 ciphertext different from plaintext', () => {
  const plainText = 'kakao-access-token-secret';
  const encrypted = encrypt(plainText);

  assert.notEqual(encrypted, plainText);
  assert.match(encrypted, /^[A-Za-z0-9+/=]+$/);
});

test('decrypt restores the original plaintext', () => {
  const plainText = 'kakao-refresh-token-secret';
  const encrypted = encrypt(plainText);

  assert.equal(decrypt(encrypted), plainText);
});

test('encrypt and decrypt return null for null input', () => {
  assert.equal(encrypt(null), null);
  assert.equal(decrypt(null), null);
});

test('resolveEncryptionKey accepts 32-byte base64 and hex keys', () => {
  const base64Key = Buffer.alloc(32, 3).toString('base64');
  const hexKey = Buffer.alloc(32, 5).toString('hex');

  assert.equal(resolveEncryptionKey(base64Key).length, 32);
  assert.equal(resolveEncryptionKey(hexKey).length, 32);
});

test('missing encryption key fails fast', () => {
  const previous = process.env.SOCIAL_TOKEN_ENCRYPTION_KEY;
  delete process.env.SOCIAL_TOKEN_ENCRYPTION_KEY;

  assert.throws(
    () => encrypt('secret-token'),
    (err) => err instanceof TokenEncryptionError
      && err.message === 'SOCIAL_TOKEN_ENCRYPTION_KEY is required',
  );

  process.env.SOCIAL_TOKEN_ENCRYPTION_KEY = previous;
});

test('decrypt rejects ciphertext encrypted with a different key', () => {
  const encrypted = encrypt('secret-token', resolveEncryptionKey(Buffer.alloc(32, 1).toString('base64')));

  assert.throws(
    () => decrypt(encrypted, resolveEncryptionKey(Buffer.alloc(32, 2).toString('base64'))),
    (err) => err instanceof TokenEncryptionError
      && err.message === 'Failed to decrypt social token',
  );
});

test('decrypt rejects corrupted ciphertext', () => {
  assert.throws(
    () => decrypt('not-valid-token-data'),
    (err) => err instanceof TokenEncryptionError,
  );
});
