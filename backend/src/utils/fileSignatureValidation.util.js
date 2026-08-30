const AppError = require('./AppError');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');
const {
  detectUploadFileSignature,
  isSupportedImageMetadata,
  isSupportedPdfMetadata,
} = require('./imageSignature');

function invalidFileType(message = 'Invalid file type') {
  return new AppError(message, {
    statusCode: HTTP_STATUS.BAD_REQUEST,
    errorCode: ERROR_CODES.INVALID_FILE_TYPE,
  });
}

async function assertImageUploadSignature(file, { allowWebp = true } = {}) {
  if (!file?.path) {
    throw invalidFileType();
  }

  const detected = await detectUploadFileSignature(file.path);
  if (!detected || detected === 'pdf' || !isSupportedImageMetadata(file, detected, { allowWebp })) {
    throw invalidFileType();
  }
}

async function assertDocumentUploadSignature(file, { imageOnly = false } = {}) {
  if (!file?.path) {
    throw invalidFileType();
  }

  if (imageOnly) {
    await assertImageUploadSignature(file, { allowWebp: true });
    return;
  }

  const detected = await detectUploadFileSignature(file.path);
  if (detected === 'pdf') {
    if (!isSupportedPdfMetadata(file, detected)) {
      throw invalidFileType();
    }
    return;
  }

  if (!isSupportedImageMetadata(file, detected, { allowWebp: true })) {
    throw invalidFileType();
  }
}

async function assertReceiptUploadSignature(file) {
  if (!file?.path) {
    throw invalidFileType();
  }

  const detected = await detectUploadFileSignature(file.path);
  if (detected === 'pdf') {
    if (!isSupportedPdfMetadata(file, detected)) {
      throw invalidFileType();
    }
    return;
  }

  if (!isSupportedImageMetadata(file, detected, { allowWebp: false })) {
    throw invalidFileType();
  }
}

module.exports = {
  assertImageUploadSignature,
  assertDocumentUploadSignature,
  assertReceiptUploadSignature,
};
