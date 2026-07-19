const fs = require('fs/promises');
const path = require('path');

const PNG_SIGNATURE = Buffer.from([
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
]);

function safeExtension(filename = '') {
  const base = path.basename(String(filename).split(/[?#]/)[0]);
  return path.extname(base).toLowerCase();
}

function detectImageSignature(buffer) {
  if (!Buffer.isBuffer(buffer)) return null;
  if (buffer.length >= PNG_SIGNATURE.length && buffer.subarray(0, PNG_SIGNATURE.length).equals(PNG_SIGNATURE)) {
    return 'png';
  }
  if (buffer.length >= 3 && buffer[0] === 0xff && buffer[1] === 0xd8 && buffer[2] === 0xff) {
    return 'jpeg';
  }
  return null;
}

async function detectImageFileSignature(filePath) {
  const handle = await fs.open(filePath, 'r');
  try {
    const buffer = Buffer.alloc(16);
    const { bytesRead } = await handle.read(buffer, 0, buffer.length, 0);
    return detectImageSignature(buffer.subarray(0, bytesRead));
  } finally {
    await handle.close();
  }
}

function isSupportedSettingsImageMetadata({ originalname, mimetype }, detectedType) {
  const ext = safeExtension(originalname);
  const mime = String(mimetype || '').toLowerCase();
  if (detectedType === 'png') {
    return ['.png'].includes(ext) && ['', 'application/octet-stream', 'image/png', 'image/x-png'].includes(mime);
  }
  if (detectedType === 'jpeg') {
    return ['.jpg', '.jpeg'].includes(ext) && ['', 'application/octet-stream', 'image/jpeg', 'image/pjpeg'].includes(mime);
  }
  return false;
}

module.exports = {
  detectImageFileSignature,
  detectImageSignature,
  isSupportedSettingsImageMetadata,
  safeExtension,
};
