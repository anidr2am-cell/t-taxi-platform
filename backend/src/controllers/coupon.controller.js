const asyncHandler = require('../utils/asyncHandler');
const { success } = require('../utils/apiResponse');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');
const AppError = require('../utils/AppError');
const container = require('../helpers/container');

const getCouponService = () => container.get('couponService');

const searchCustomers = asyncHandler(async (req, res) => {
  const customers = await getCouponService().searchCustomers(req.query.query);
  return success(res, customers, 'OK');
});

const listRecentCustomers = asyncHandler(async (req, res) => {
  const customers = await getCouponService().listRecentCompletedCustomers(req.query.limit);
  return success(res, customers, 'OK');
});

const issueCoupon = asyncHandler(async (req, res) => {
  const coupon = await getCouponService().issueCoupon({
    customerUserId: req.body.customerUserId,
    title: req.body.title,
    discountAmount: req.body.discountAmount,
    templateId: req.body.templateId,
    issuedByAdminId: req.user.id,
  });
  return success(res, coupon, 'Coupon issued', 201);
});

const cancelCoupon = asyncHandler(async (req, res) => {
  await getCouponService().cancelCoupon(Number(req.params.id));
  return success(res, null, 'Coupon cancelled');
});

const listRecentCoupons = asyncHandler(async (req, res) => {
  const coupons = await getCouponService().listRecentIssued(req.query.limit);
  return success(res, coupons, 'OK');
});

const listMyCoupons = asyncHandler(async (req, res) => {
  const coupons = await getCouponService().listCouponsForCustomer(req.user.id);
  return success(res, coupons, 'OK');
});

const streamCustomerCouponImage = asyncHandler(async (req, res) => {
  const absolutePath = await getCouponService().getCustomerCouponImagePath(
    Number(req.params.id),
    req.user.id,
  );
  res.setHeader('Cache-Control', 'private, max-age=3600');
  return res.sendFile(absolutePath);
});

const createTemplate = asyncHandler(async (req, res) => {
  const template = await getCouponService().createTemplate({
    title: req.body.title,
    discountAmount: Number(req.body.discountAmount),
    file: req.file,
    createdByAdminId: req.user.id,
  });
  return success(res, template, 'Coupon template created', HTTP_STATUS.CREATED);
});

const listTemplates = asyncHandler(async (req, res) => {
  const templates = await getCouponService().listTemplates();
  return success(res, templates, 'OK');
});

const updateTemplate = asyncHandler(async (req, res) => {
  const template = await getCouponService().setTemplateActive(
    Number(req.params.id),
    req.body.isActive,
  );
  return success(res, template, 'Coupon template updated');
});

const streamTemplateImage = asyncHandler(async (req, res) => {
  const absolutePath = await getCouponService().getTemplateImagePath(Number(req.params.id));
  res.setHeader('Cache-Control', 'private, max-age=3600');
  return res.sendFile(absolutePath);
});

const handleUploadError = (err, req, res, next) => {
  if (err?.code === 'LIMIT_FILE_SIZE') {
    return next(new AppError('Coupon image file is too large', {
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
  searchCustomers,
  listRecentCustomers,
  issueCoupon,
  cancelCoupon,
  listRecentCoupons,
  listMyCoupons,
  streamCustomerCouponImage,
  createTemplate,
  listTemplates,
  updateTemplate,
  streamTemplateImage,
  handleUploadError,
};
