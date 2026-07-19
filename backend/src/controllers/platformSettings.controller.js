const asyncHandler = require('../utils/asyncHandler');
const { success } = require('../utils/apiResponse');
const container = require('../helpers/container');
const AppError = require('../utils/AppError');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');

const service = () => container.get('platformSettingsService');

const getPublic = asyncHandler(async (_req, res) => success(res, await service().getPublic()));
const getAdmin = asyncHandler(async (_req, res) => success(res, await service().getAdmin()));
const updateAdmin = asyncHandler(async (req, res) => success(
  res, await service().update(req.body, req.user.id), 'Settings updated',
));
const uploadImage = asyncHandler(async (req, res) => success(
  res, await service().saveImage(req.params.kind, req.file, req.user.id), 'Image updated',
));
const getAsset = asyncHandler(async (req, res) => {
  res.setHeader('Cache-Control', 'no-store');
  return res.sendFile(await service().getImage(req.params.kind));
});

const handleUploadError = (err, req, res, next) => {
  if (err?.code === 'LIMIT_FILE_SIZE') {
    return next(new AppError('Settings image file is too large', {
      statusCode: HTTP_STATUS.BAD_REQUEST,
      errorCode: ERROR_CODES.FILE_TOO_LARGE,
    }));
  }
  if (err?.code === 'LIMIT_UNEXPECTED_FILE') {
    return next(new AppError('Only PNG and JPEG images are supported', {
      statusCode: HTTP_STATUS.BAD_REQUEST,
      errorCode: ERROR_CODES.INVALID_SETTINGS_IMAGE,
    }));
  }
  if (err?.message === 'INVALID_FILE_TYPE') {
    return next(new AppError('Only PNG and JPEG images are supported', {
      statusCode: HTTP_STATUS.BAD_REQUEST,
      errorCode: ERROR_CODES.INVALID_SETTINGS_IMAGE,
    }));
  }
  return next(err);
};

module.exports = {
  getPublic,
  getAdmin,
  updateAdmin,
  uploadImage,
  getAsset,
  handleUploadError,
};
