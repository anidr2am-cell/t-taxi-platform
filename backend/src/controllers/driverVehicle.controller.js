const path = require('path');
const asyncHandler = require('../utils/asyncHandler');
const { success, paginate } = require('../utils/apiResponse');
const container = require('../helpers/container');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');
const { uploadDir } = require('../config/multer');

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

const listAdmin = asyncHandler(async (req, res) => {
  const data = await getDriverVehicleService().listAdmin(req.query);
  return paginate(res, {
    page: data.page,
    pageSize: data.pageSize,
    total: data.total,
    items: data.items,
  });
});

const getAdminDetail = asyncHandler(async (req, res) => {
  const data = await getDriverVehicleService().getAdminDetail(Number(req.params.id));
  return success(res, data, 'OK');
});

const getAdminFile = asyncHandler(async (req, res) => {
  const file = await getDriverVehicleService().getAdminFile(
    Number(req.params.id),
    Number(req.params.fileId),
  );
  const absolute = path.join(uploadDir, file.filePath);
  return res.sendFile(absolute, {
    headers: {
      'Content-Type': file.mimeType || 'application/octet-stream',
      'Content-Disposition': `inline; filename="${file.originalFilename || 'document'}"`,
    },
  });
});

const approve = asyncHandler(async (req, res) => {
  const data = await getDriverVehicleService().approve(
    Number(req.params.id),
    req.body,
    req.user,
    { ipAddress: req.ip },
  );
  return success(res, data, 'Driver vehicle approved');
});

const reject = asyncHandler(async (req, res) => {
  const data = await getDriverVehicleService().reject(
    Number(req.params.id),
    req.body,
    req.user,
    { ipAddress: req.ip },
  );
  return success(res, data, 'Driver vehicle rejected');
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
  listAdmin,
  getAdminDetail,
  getAdminFile,
  approve,
  reject,
  normalizeMultipartBody,
  handleUploadError,
};
