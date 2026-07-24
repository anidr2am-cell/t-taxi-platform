const path = require('path');
const fs = require('fs');
const asyncHandler = require('../utils/asyncHandler');
const { success } = require('../utils/apiResponse');
const { uploadDir } = require('../config/multer');
const container = require('../helpers/container');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');

const getDriverProfileService = () => container.get('driverProfileService');

const getProfile = asyncHandler(async (req, res) => {
  const data = await getDriverProfileService().getProfile(req.user.id);
  return success(res, data, 'OK');
});

const updateProfile = asyncHandler(async (req, res) => {
  const data = await getDriverProfileService().updateProfile(req.user.id, req.body);
  return success(res, data, 'Profile updated');
});

const uploadAvatar = asyncHandler(async (req, res) => {
  const data = await getDriverProfileService().uploadAvatar(req.user.id, req.file);
  return success(res, data, 'Avatar updated');
});

const uploadVehiclePhoto = asyncHandler(async (req, res) => {
  const data = await getDriverProfileService().uploadVehiclePhoto(req.user.id, req.file);
  return success(res, data, 'Vehicle photo updated');
});

const streamAvatar = asyncHandler(async (req, res) => {
  const file = await getDriverProfileService().streamAvatar(req.user.id);
  const absolutePath = path.join(uploadDir, file.file_path);
  if (!fs.existsSync(absolutePath)) {
    return res.status(HTTP_STATUS.NOT_FOUND).json({
      success: false,
      message: 'File not found',
      error_code: ERROR_CODES.FILE_NOT_FOUND,
    });
  }
  res.setHeader('Content-Type', file.mime_type || 'application/octet-stream');
  return res.sendFile(path.resolve(absolutePath));
});

const streamVehiclePhoto = asyncHandler(async (req, res) => {
  const file = await getDriverProfileService().streamVehiclePhoto(req.user.id);
  const absolutePath = path.join(uploadDir, file.file_path);
  if (!fs.existsSync(absolutePath)) {
    return res.status(HTTP_STATUS.NOT_FOUND).json({
      success: false,
      message: 'File not found',
      error_code: ERROR_CODES.FILE_NOT_FOUND,
    });
  }
  res.setHeader('Content-Type', file.mime_type || 'application/octet-stream');
  return res.sendFile(path.resolve(absolutePath));
});

const handleUploadError = (err, req, res, next) => {
  if (err?.message === 'INVALID_FILE_TYPE') {
    return res.status(HTTP_STATUS.BAD_REQUEST).json({
      success: false,
      message: 'Invalid file type',
      error_code: ERROR_CODES.INVALID_FILE_TYPE,
    });
  }
  if (err?.code === 'LIMIT_FILE_SIZE') {
    return res.status(HTTP_STATUS.BAD_REQUEST).json({
      success: false,
      message: 'File too large',
      error_code: ERROR_CODES.FILE_TOO_LARGE,
    });
  }
  return next(err);
};

module.exports = {
  getProfile,
  updateProfile,
  uploadAvatar,
  uploadVehiclePhoto,
  streamAvatar,
  streamVehiclePhoto,
  handleUploadError,
};
