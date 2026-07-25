const asyncHandler = require('../utils/asyncHandler');
const { success } = require('../utils/apiResponse');
const container = require('../helpers/container');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');

const getDriverVehicleService = () => container.get('driverVehicleService');

const listVehicles = asyncHandler(async (req, res) => {
  const data = await getDriverVehicleService().listVehicles(req.user.id);
  return success(res, data, 'OK');
});

const createVehicle = asyncHandler(async (req, res) => {
  const data = await getDriverVehicleService().createVehicle(
    req.user.id,
    req.body,
    req.files || {},
  );
  return success(res, data, 'Vehicle submitted for approval', HTTP_STATUS.CREATED);
});

const normalizeMultipartBody = (req, res, next) => {
  if (req.body && typeof req.body === 'object') {
    if (req.body.vehicleTypeId != null && req.body.vehicleTypeId !== '') {
      const n = Number(req.body.vehicleTypeId);
      if (Number.isFinite(n)) req.body.vehicleTypeId = n;
    }
    for (const key of ['modelName', 'color', 'plateNumber']) {
      if (typeof req.body[key] === 'string') {
        req.body[key] = req.body[key].trim();
      }
    }
  }
  return next();
};

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
  listVehicles,
  createVehicle,
  normalizeMultipartBody,
  handleUploadError,
};
