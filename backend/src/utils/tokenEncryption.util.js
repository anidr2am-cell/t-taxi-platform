const crypto = require('crypto');

const ALGORITHM = 'aes-256-gcm';
const IV_LENGTH = 12;
const AUTH_TAG_LENGTH = 16;
const KEY_LENGTH = 32;

class TokenEncryptionError extends Error {
  constructor(message) {
    super(message);
    this.name = 'TokenEncryptionError';
  }
}

function resolveEncryptionKey(rawKey) {
  if (rawKey == null || String(rawKey).trim() === '') {
    throw new TokenEncryptionError('SOCIAL_TOKEN_ENCRYPTION_KEY is required');
  }

  const trimmed = String(rawKey).trim();
  let keyBuffer;

  if (/^[0-9a-fA-F]{64}$/.test(trimmed)) {
    keyBuffer = Buffer.from(trimmed, 'hex');
  } else {
    keyBuffer = Buffer.from(trimmed, 'base64');
  }

  if (keyBuffer.length !== KEY_LENGTH) {
    throw new TokenEncryptionError(
      'SOCIAL_TOKEN_ENCRYPTION_KEY must decode to 32 bytes (256 bits)',
    );
  }

  return keyBuffer;
}

function getEncryptionKey() {
  return resolveEncryptionKey(process.env.SOCIAL_TOKEN_ENCRYPTION_KEY);
}

function encrypt(plainText, key = getEncryptionKey()) {
  if (plainText == null) {
    return null;
  }
  if (typeof plainText !== 'string') {
    throw new TokenEncryptionError('Token plaintext must be a string');
  }

  const iv = crypto.randomBytes(IV_LENGTH);
  const cipher = crypto.createCipheriv(ALGORITHM, key, iv);
  const encrypted = Buffer.concat([
    cipher.update(plainText, 'utf8'),
    cipher.final(),
  ]);
  const authTag = cipher.getAuthTag();

  return Buffer.concat([iv, authTag, encrypted]).toString('base64');
}

function decrypt(encryptedText, key = getEncryptionKey()) {
  if (encryptedText == null) {
    return null;
  }
  if (typeof encryptedText !== 'string') {
    throw new TokenEncryptionError('Encrypted token must be a string');
  }

  let payload;
  try {
    payload = Buffer.from(encryptedText, 'base64');
  } catch (err) {
    throw new TokenEncryptionError('Encrypted token is not valid base64');
  }

  if (payload.length < IV_LENGTH + AUTH_TAG_LENGTH + 1) {
    throw new TokenEncryptionError('Encrypted token payload is too short');
  }

  const iv = payload.subarray(0, IV_LENGTH);
  const authTag = payload.subarray(IV_LENGTH, IV_LENGTH + AUTH_TAG_LENGTH);
  const ciphertext = payload.subarray(IV_LENGTH + AUTH_TAG_LENGTH);

  try {
    const decipher = crypto.createDecipheriv(ALGORITHM, key, iv);
    decipher.setAuthTag(authTag);
    const decrypted = Buffer.concat([
      decipher.update(ciphertext),
      decipher.final(),
    ]);
    return decrypted.toString('utf8');
  } catch (err) {
    throw new TokenEncryptionError('Failed to decrypt social token');
  }
}

module.exports = {
  encrypt,
  decrypt,
  resolveEncryptionKey,
  TokenEncryptionError,
};
