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

const recommendVehicle = asyncHandler(async (req, res) => {
  const data = await getVehicleRecommendationService().recommend(req.body);
  return success(res, data, data.message);
});

const createBooking = asyncHandler(async (req, res) => {
  const data = await getBookingService().createBooking(req.body, req.user);
  return success(res, data, 'Booking created', HTTP_STATUS.CREATED);
});

const updateBookingStatus = asyncHandler(async (req, res) => {
  const data = await getBookingStatusService().transition(
    req.params.bookingNumber,
    req.body,
    req.user,
  );
  return success(res, data, 'Booking status updated');
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
  issueDropoffQr,
  issueBoardingQr,
  lookupGuestBooking,
  getGuestAssignedDriverVehiclePhoto,
};
