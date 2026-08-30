const fs = require('fs/promises');
const path = require('path');

const PNG_SIGNATURE = Buffer.from([
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
]);
const WEBP_RIFF = Buffer.from('RIFF');
const WEBP_MARKER = Buffer.from('WEBP');
const PDF_MARKER = Buffer.from('%PDF');
const GENERIC_MIME_TYPES = new Set(['', 'application/octet-stream']);

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
  if (
    buffer.length >= 12
    && buffer.subarray(0, 4).equals(WEBP_RIFF)
    && buffer.subarray(8, 12).equals(WEBP_MARKER)
  ) {
    return 'webp';
  }
  return null;
}

function detectPdfSignature(buffer) {
  if (!Buffer.isBuffer(buffer) || buffer.length < PDF_MARKER.length) return false;
  return buffer.subarray(0, PDF_MARKER.length).equals(PDF_MARKER);
}

async function detectUploadFileSignature(filePath) {
  const handle = await fs.open(filePath, 'r');
  try {
    const buffer = Buffer.alloc(16);
    const { bytesRead } = await handle.read(buffer, 0, buffer.length, 0);
    const slice = buffer.subarray(0, bytesRead);
    if (detectPdfSignature(slice)) {
      return 'pdf';
    }
    return detectImageSignature(slice);
  } finally {
    await handle.close();
  }
}

async function detectImageFileSignature(filePath) {
  const detected = await detectUploadFileSignature(filePath);
  return detected === 'pdf' ? null : detected;
}

function isSupportedImageMetadata(file, detectedType, { allowWebp = true } = {}) {
  const ext = safeExtension(file?.originalname || file?.filename);
  const mime = String(file?.mimetype || '').toLowerCase();

  if (detectedType === 'png') {
    return ext === '.png'
      && (GENERIC_MIME_TYPES.has(mime) || ['image/png', 'image/x-png'].includes(mime));
  }
  if (detectedType === 'jpeg') {
    return ['.jpg', '.jpeg'].includes(ext)
      && (GENERIC_MIME_TYPES.has(mime) || ['image/jpeg', 'image/pjpeg'].includes(mime));
  }
  if (detectedType === 'webp' && allowWebp) {
    return ext === '.webp'
      && (GENERIC_MIME_TYPES.has(mime) || mime === 'image/webp');
  }
  return false;
}

function isSupportedPdfMetadata(file, detectedType) {
  if (detectedType !== 'pdf') return false;
  const ext = safeExtension(file?.originalname || file?.filename);
  const mime = String(file?.mimetype || '').toLowerCase();
  return ext === '.pdf'
    && (GENERIC_MIME_TYPES.has(mime) || mime === 'application/pdf');
}

function isSupportedSettingsImageMetadata(file, detectedType) {
  return isSupportedImageMetadata(file, detectedType, { allowWebp: false });
}

module.exports = {
  detectImageFileSignature,
  detectImageSignature,
  detectUploadFileSignature,
  isSupportedImageMetadata,
  isSupportedPdfMetadata,
  isSupportedSettingsImageMetadata,
  safeExtension,
};
