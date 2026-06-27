const asyncHandler = require('../utils/asyncHandler');
const { success, paginate } = require('../utils/apiResponse');
const container = require('../helpers/container');
const config = require('../config');
const AppError = require('../utils/AppError');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');

const getSettlementService = () => container.get('commissionSettlementService');

function settlementApiBase(segment) {
  return `/api/${config.server.apiVersion}/${segment}`;
}

const listDriverSettlements = asyncHandler(async (req, res) => {
  const apiBase = settlementApiBase('driver/settlements');
  const items = await getSettlementService().listDriverSettlements(req.user.id, apiBase);
  return success(res, { items });
});

const getDriverSettlement = asyncHandler(async (req, res) => {
  const apiBase = settlementApiBase('driver/settlements');
  const data = await getSettlementService().getDriverSettlement(
    req.user.id,
    req.params.bookingNumber,
    apiBase,
  );
  return success(res, data);
});

const uploadDriverReceipt = asyncHandler(async (req, res) => {
  const data = await getSettlementService().uploadReceipt(
    req.user.id,
    req.params.bookingNumber,
    req.file,
  );
  return success(res, data, 'Receipt uploaded');
});

const getDriverReceipt = asyncHandler(async (req, res) => {
  const file = await getSettlementService().getReceiptFileForActor(
    req.user,
    req.params.bookingNumber,
    req.user.role,
  );
  res.setHeader('Content-Type', file.mimeType);
  res.setHeader('Content-Disposition', `inline; filename="${file.fileName.replace(/"/g, '')}"`);
  return res.sendFile(file.absolutePath);
});

const listAdminSettlements = asyncHandler(async (req, res) => {
  const apiBase = settlementApiBase('admin/settlements');
  const data = await getSettlementService().listAdminSettlements(req.query, apiBase);
  return paginate(res, {
    page: data.page,
    pageSize: data.pageSize,
    total: data.total,
    items: data.items,
  });
});

const getAdminSettlement = asyncHandler(async (req, res) => {
  const apiBase = settlementApiBase('admin/settlements');
  const data = await getSettlementService().getAdminSettlement(
    req.params.bookingNumber,
    apiBase,
  );
  return success(res, data);
});

const approveSettlement = asyncHandler(async (req, res) => {
  const data = await getSettlementService().approve(
    req.params.bookingNumber,
    req.user,
  );
  return success(res, data, 'Settlement approved');
});

const rejectSettlement = asyncHandler(async (req, res) => {
  const data = await getSettlementService().reject(
    req.params.bookingNumber,
    req.body.reason,
    req.user,
  );
  return success(res, data, 'Settlement rejected');
});

const getAdminReceipt = asyncHandler(async (req, res) => {
  const file = await getSettlementService().getReceiptFileForActor(
    req.user,
    req.params.bookingNumber,
    req.user.role,
  );
  res.setHeader('Content-Type', file.mimeType);
  res.setHeader('Content-Disposition', `inline; filename="${file.fileName.replace(/"/g, '')}"`);
  return res.sendFile(file.absolutePath);
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
  listDriverSettlements,
  getDriverSettlement,
  uploadDriverReceipt,
  getDriverReceipt,
  listAdminSettlements,
  getAdminSettlement,
  approveSettlement,
  rejectSettlement,
  getAdminReceipt,
  handleUploadError,
};
