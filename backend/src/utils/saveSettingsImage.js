const fs = require('fs/promises');
const path = require('path');
const AppError = require('../utils/AppError');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');
const { uploadDir } = require('../config/multer');
const {
  detectImageFileSignature,
  isSupportedSettingsImageMetadata,
} = require('./imageSignature');

function invalidSettingsImageError() {
  return new AppError('Only PNG and JPEG images are supported', {
    statusCode: HTTP_STATUS.BAD_REQUEST,
    errorCode: ERROR_CODES.INVALID_SETTINGS_IMAGE,
  });
}

async function cleanupUploadedFile(file) {
  if (!file?.path) return;
  try {
    await fs.unlink(file.path);
  } catch (_) {
    // ignore cleanup failures
  }
}

async function saveSettingsImage(file) {
  if (!file) {
    throw invalidSettingsImageError();
  }
  let detectedType = null;
  try {
    detectedType = await detectImageFileSignature(file.path);
  } catch (_) {
    await cleanupUploadedFile(file);
    throw invalidSettingsImageError();
  }
  if (!isSupportedSettingsImageMetadata(file, detectedType)) {
    await cleanupUploadedFile(file);
    throw invalidSettingsImageError();
  }
  return path.relative(uploadDir, file.path).replace(/\\/g, '/');
}

function resolveUploadAbsolutePath(relativePath) {
  if (!relativePath) {
    throw new AppError('File not found', {
      statusCode: HTTP_STATUS.NOT_FOUND,
      errorCode: ERROR_CODES.FILE_NOT_FOUND,
    });
  }
  const absolutePath = path.resolve(uploadDir, String(relativePath));
  const root = `${path.resolve(uploadDir)}${path.sep}`;
  if (absolutePath !== path.resolve(uploadDir) && !absolutePath.startsWith(root)) {
    throw new AppError('Invalid file path', {
      statusCode: HTTP_STATUS.BAD_REQUEST,
      errorCode: ERROR_CODES.FILE_NOT_FOUND,
    });
  }
  return absolutePath;
}

async function deleteStoredImage(relativePath) {
  if (!relativePath) return;
  try {
    await fs.unlink(resolveUploadAbsolutePath(relativePath));
  } catch (_) {
    // ignore missing files during hard delete
  }
}

module.exports = {
  saveSettingsImage,
  resolveUploadAbsolutePath,
  deleteStoredImage,
  cleanupUploadedFile,
  invalidSettingsImageError,
};
