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

const fileFilter = (req, file, cb) => {
  if (allowedMimePrefixes.some((p) => file.mimetype.startsWith(p))) {
    cb(null, true);
  } else {
    cb(new Error('INVALID_FILE_TYPE'), false);
  }
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
