const asyncHandler = require('../utils/asyncHandler');
const path = require('path');
const { success } = require('../utils/apiResponse');
const AppError = require('../utils/AppError');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');
const container = require('../helpers/container');
const { extractGuestAccessTokenFromHeader } = require('../utils/guestAccess.util');
const { resolveUploadAbsolutePath } = require('../utils/uploadPath.util');

const getBookingNameSignPhotoService = () => container.get('bookingNameSignPhotoService');
const getGuestNameSignPhotoService = () => container.get('guestNameSignPhotoService');

const uploadDriverNameSignPhoto = asyncHandler(async (req, res) => {
  const data = await getBookingNameSignPhotoService().upload(
    req.user.id,
    req.params.bookingNumber,
    req.file,
  );
  return success(res, data, 'Name sign photo uploaded');
});

const getDriverNameSignPhoto = asyncHandler(async (req, res) => {
  const file = await getBookingNameSignPhotoService().getDriverFile(
    req.user.id,
    req.params.bookingNumber,
  );
  res.setHeader('Content-Type', file.mimeType);
  res.setHeader('Content-Disposition', `inline; filename="${file.fileName.replace(/"/g, '')}"`);
  return res.sendFile(file.absolutePath);
});

const getGuestNameSignPhoto = asyncHandler(async (req, res) => {
  const file = await getGuestNameSignPhotoService().getNameSignPhotoFile(
    Number(req.params.bookingId),
    extractGuestAccessTokenFromHeader(req),
  );
  res.setHeader('Cache-Control', 'private, max-age=300');
  res.type(file.mimeType || 'application/octet-stream');
  return res.sendFile(resolveUploadAbsolutePath(file.filePath));
});

const handleUploadError = (err, req, res, next) => {
  if (err?.code === 'LIMIT_FILE_SIZE') {
    return next(new AppError('File too large', {
      statusCode: HTTP_STATUS.BAD_REQUEST,
      errorCode: ERROR_CODES.FILE_TOO_LARGE,
    }));
  }
  if (err?.message === 'INVALID_FILE_TYPE') {
    return next(new AppError('Invalid file type', {
      statusCode: HTTP_STATUS.BAD_REQUEST,
      errorCode: ERROR_CODES.INVALID_FILE_TYPE,
    }));
  }
  return next(err);
};

module.exports = {
  uploadDriverNameSignPhoto,
  getDriverNameSignPhoto,
  getGuestNameSignPhoto,
  handleUploadError,
};
