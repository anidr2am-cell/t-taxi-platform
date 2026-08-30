const path = require('path');
const AppError = require('./AppError');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');
const { uploadDir } = require('../config/multer');

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

module.exports = {
  resolveUploadAbsolutePath,
};
