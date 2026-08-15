const asyncHandler = require('../utils/asyncHandler');
const path = require('path');
const { success } = require('../utils/apiResponse');
const HTTP_STATUS = require('../constants/httpStatus');
const container = require('../helpers/container');
const { extractGuestAccessTokenFromHeader } = require('../utils/guestAccess.util');
const { uploadDir } = require('../config/multer');

const getVehicleRecommendationService = () => container.get('vehicleRecommendationService');
const getBookingService = () => container.get('bookingService');
const getBookingStatusService = () => container.get('bookingStatusService');
const getGuestBookingLookupService = () => container.get('guestBookingLookupService');
const getGuestVehiclePhotoService = () => container.get('guestVehiclePhotoService');
const getUrgentNegotiationService = () => container.get('urgentNegotiationService');

const recommendVehicle = asyncHandler(async (req, res) => {
  const data = await getVehicleRecommendationService().recommend(req.body);
  return success(res, data, data.message);
});

const {
  normalizeIdempotencyKey,
  isIdempotencyKeyRequired,
} = require('../utils/bookingIdempotency.util');
const AppError = require('../utils/AppError');
const ERROR_CODES = require('../constants/errorCodes');
const config = require('../config');

const createBooking = asyncHandler(async (req, res) => {
  const rawIdempotencyKey = req.get('Idempotency-Key');
  if (isIdempotencyKeyRequired(config.server.nodeEnv)) {
    if (rawIdempotencyKey === undefined || rawIdempotencyKey === null || !String(rawIdempotencyKey).trim()) {
      throw new AppError(
        'Idempotency-Key header is required. Send a unique client-generated key per booking submit attempt and reuse it on retries.',
        {
          statusCode: HTTP_STATUS.BAD_REQUEST,
          errorCode: ERROR_CODES.IDEMPOTENCY_KEY_REQUIRED,
        },
      );
    }
  }

  const normalizedKey = normalizeIdempotencyKey(rawIdempotencyKey);
  if (normalizedKey?.invalid) {
    throw new AppError('Invalid Idempotency-Key header', {
      statusCode: HTTP_STATUS.BAD_REQUEST,
      errorCode: ERROR_CODES.VALIDATION_ERROR,
    });
  }

  const result = await getBookingService().createBooking(req.body, req.user, {
    idempotencyKey: normalizedKey?.value ?? null,
  });
  const statusCode = result.replayed ? HTTP_STATUS.OK : result.responseStatus;
  return success(res, result.data, 'Booking created', statusCode);
});

const updateBookingStatus = asyncHandler(async (req, res) => {
  const data = await getBookingStatusService().transition(
    req.params.bookingNumber,
    req.body,
    req.user,
  );
  return success(res, data, 'Booking status updated');
});

const cancelBooking = asyncHandler(async (req, res) => {
  const guestAccessToken =
    req.body?.guestAccessToken || extractGuestAccessTokenFromHeader(req);
  const data = await getBookingStatusService().cancelByCustomer(
    req.params.bookingNumber,
    {
      ...req.body,
      guestAccessToken,
    },
    req.user || null,
  );
  return success(res, data, 'Booking cancelled');
});

const submitUrgentDecision = asyncHandler(async (req, res) => {
  const guestAccessToken =
    req.body?.guestAccessToken || extractGuestAccessTokenFromHeader(req);
  const data = await getUrgentNegotiationService().submitCustomerDecision(
    req.params.bookingNumber,
    req.body.decision,
    {
      authUser: req.user || null,
      guestAccessToken,
    },
  );
  return success(res, data, 'OK');
});

const getUrgentNegotiation = asyncHandler(async (req, res) => {
  const guestAccessToken = extractGuestAccessTokenFromHeader(req);
  const data = await getUrgentNegotiationService().getCustomerNegotiationStatus(
    req.params.bookingNumber,
    {
      authUser: req.user || null,
      guestAccessToken,
    },
  );
  return success(res, data, 'OK');
});

const issueDropoffQr = asyncHandler(async (req, res) => {
  const data = await getBookingService().issueDropoffQr(
    req.params.bookingNumber,
    req.body,
    req.user,
  );
  return success(res, data, 'Dropoff QR issued');
});

const issueBoardingQr = asyncHandler(async (req, res) => {
  const data = await getBookingService().issueBoardingQr(
    req.params.bookingNumber,
    req.body,
    req.user,
  );
  return success(res, data, 'Boarding QR issued');
});

const lookupGuestBooking = asyncHandler(async (req, res) => {
  const data = await getGuestBookingLookupService().lookup(req.body);
  return success(res, data, 'Booking found');
});

const getGuestAssignedDriverVehiclePhoto = asyncHandler(async (req, res) => {
  const file = await getGuestVehiclePhotoService().getAssignedDriverVehiclePhotoFile(
    Number(req.params.bookingId),
    extractGuestAccessTokenFromHeader(req),
  );
  res.setHeader('Cache-Control', 'private, max-age=300');
  res.type(file.mimeType || 'application/octet-stream');
  return res.sendFile(path.resolve(uploadDir, file.filePath));
});

module.exports = {
  recommendVehicle,
  createBooking,
  updateBookingStatus,
  cancelBooking,
  submitUrgentDecision,
  getUrgentNegotiation,
  issueDropoffQr,
  issueBoardingQr,
  lookupGuestBooking,
  getGuestAssignedDriverVehiclePhoto,
};
