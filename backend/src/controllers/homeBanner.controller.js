const asyncHandler = require('../utils/asyncHandler');
const { success } = require('../utils/apiResponse');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');
const AppError = require('../utils/AppError');
const container = require('../helpers/container');

const getHomeBannerService = () => container.get('homeBannerService');

const listAdminBanners = asyncHandler(async (req, res) => {
  const banners = await getHomeBannerService().listAdminBanners();
  return success(res, banners, 'OK');
});

const createBanner = asyncHandler(async (req, res) => {
  const banner = await getHomeBannerService().createBanner({
    file: req.file,
    displayOrder: req.body.displayOrder != null ? Number(req.body.displayOrder) : null,
    createdByAdminId: req.user.id,
  });
  return success(res, banner, 'Home banner created', HTTP_STATUS.CREATED);
});

const updateBanner = asyncHandler(async (req, res) => {
  const banner = await getHomeBannerService().updateBanner(Number(req.params.id), {
    isActive: req.body.isActive,
    displayOrder: req.body.displayOrder,
  });
  return success(res, banner, 'Home banner updated');
});

const deleteBanner = asyncHandler(async (req, res) => {
  await getHomeBannerService().deleteBanner(Number(req.params.id));
  return success(res, null, 'Home banner deleted');
});

const streamAdminBannerImage = asyncHandler(async (req, res) => {
  const absolutePath = await getHomeBannerService().getAdminImagePath(Number(req.params.id));
  res.setHeader('Cache-Control', 'private, max-age=3600');
  return res.sendFile(absolutePath);
});

const listPublicBanners = asyncHandler(async (req, res) => {
  const banners = await getHomeBannerService().listPublicBanners();
  return success(res, banners, 'OK');
});

const streamPublicBannerImage = asyncHandler(async (req, res) => {
  const absolutePath = await getHomeBannerService().getPublicImagePath(Number(req.params.id));
  res.setHeader('Cache-Control', 'public, max-age=3600');
  return res.sendFile(absolutePath);
});

const handleUploadError = (err, req, res, next) => {
  if (err?.code === 'LIMIT_FILE_SIZE') {
    return next(new AppError('Banner image file is too large', {
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
  listAdminBanners,
  createBanner,
  updateBanner,
  deleteBanner,
  streamAdminBannerImage,
  listPublicBanners,
  streamPublicBannerImage,
  handleUploadError,
};
