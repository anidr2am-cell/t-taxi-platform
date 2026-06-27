const asyncHandler = require('../utils/asyncHandler');
const { success, paginate } = require('../utils/apiResponse');
const HTTP_STATUS = require('../constants/httpStatus');
const container = require('../helpers/container');
const { extractGuestAccessTokenFromHeader } = require('../utils/guestAccess.util');

const getReviewService = () => container.get('reviewService');

const getBookingReview = asyncHandler(async (req, res) => {
  const data = await getReviewService().getBookingReview(
    req.params.bookingNumber,
    req.user ?? null,
    extractGuestAccessTokenFromHeader(req),
  );
  return success(res, data);
});

const submitBookingReview = asyncHandler(async (req, res) => {
  const data = await getReviewService().submitBookingReview(
    req.params.bookingNumber,
    req.body,
    req.user ?? null,
  );
  return success(res, data, 'Review submitted', HTTP_STATUS.CREATED);
});

const listAdminReviews = asyncHandler(async (req, res) => {
  const data = await getReviewService().listAdminReviews(req.query);
  return paginate(res, {
    page: data.page,
    pageSize: data.pageSize,
    total: data.total,
    items: data.items,
  });
});

const getAdminReview = asyncHandler(async (req, res) => {
  const data = await getReviewService().getAdminReview(Number(req.params.reviewId));
  return success(res, data);
});

const hideAdminReview = asyncHandler(async (req, res) => {
  const data = await getReviewService().hideReview(
    Number(req.params.reviewId),
    req.body.reason,
    req.user,
  );
  return success(res, data, 'Review hidden');
});

const restoreAdminReview = asyncHandler(async (req, res) => {
  const data = await getReviewService().restoreReview(
    Number(req.params.reviewId),
    req.user,
  );
  return success(res, data, 'Review restored');
});

const getDriverRatingSummary = asyncHandler(async (req, res) => {
  const data = await getReviewService().getDriverRatingSummary(req.user.id);
  return success(res, data);
});

module.exports = {
  getBookingReview,
  submitBookingReview,
  listAdminReviews,
  getAdminReview,
  hideAdminReview,
  restoreAdminReview,
  getDriverRatingSummary,
};
