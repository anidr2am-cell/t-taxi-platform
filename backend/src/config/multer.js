/**
 * config/multer.js — File upload (chat images, etc.)
 *
 * Storage: local disk first → S3 adapter in services layer (later phase)
 */
const path = require('path');
const fs = require('fs');
const multer = require('multer');
const env = require('./env');
const uploadDir = path.resolve(process.cwd(), env.upload.dir);

if (!fs.existsSync(uploadDir)) {
  fs.mkdirSync(uploadDir, { recursive: true });
}

const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    const sub = path.join(uploadDir, new Date().toISOString().slice(0, 10));
    fs.mkdirSync(sub, { recursive: true });
    cb(null, sub);
  },
  filename: (req, file, cb) => {
    const unique = `${Date.now()}-${Math.round(Math.random() * 1e9)}`;
    const ext = path.extname(file.originalname) || '';
    cb(null, `${unique}${ext}`);
  },
});

const allowedMimePrefixes = ['image/', 'application/pdf'];
const allowedGenericExtensions = new Set(['.jpg', '.jpeg', '.png', '.webp', '.pdf']);
const blockedExtensions = new Set([
  '.exe',
  '.js',
  '.mjs',
  '.cjs',
  '.html',
  '.htm',
  '.svg',
  '.bat',
  '.cmd',
  '.ps1',
  '.sh',
]);

const safeExt = (filename = '') => {
  const base = path.basename(String(filename).split(/[?#]/)[0]);
  return path.extname(base).toLowerCase();
};

const invalidFileTypeError = (file, reason) => {
  const err = new Error('INVALID_FILE_TYPE');
  err.fieldName = file?.fieldname;
  err.fileName = path.basename(String(file?.originalname || '').split(/[?#]/)[0]);
  err.mimeType = file?.mimetype || '';
  err.reason = reason;
  return err;
};

const fileFilter = (req, file, cb) => {
  const ext = safeExt(file.originalname);
  const mime = String(file.mimetype || '').toLowerCase();

  if (!ext || blockedExtensions.has(ext)) {
    cb(invalidFileTypeError(file, 'blocked_extension'), false);
    return;
  }

  if (allowedMimePrefixes.some((p) => mime.startsWith(p))) {
    cb(null, true);
    return;
  }

  if ((mime === '' || mime === 'application/octet-stream') && allowedGenericExtensions.has(ext)) {
    cb(null, true);
    return;
  }

  cb(invalidFileTypeError(file, 'unsupported_mime'), false);
};

const upload = multer({
  storage,
  limits: { fileSize: env.upload.maxFileSizeBytes },
  fileFilter,
});

module.exports = {
  upload,
  uploadDir,
  single: upload.single('file'),
};
