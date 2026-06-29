const asyncHandler = require('../utils/asyncHandler');
const { success } = require('../utils/apiResponse');
const HTTP_STATUS = require('../constants/httpStatus');
const container = require('../helpers/container');

const getVehicleRecommendationService = () => container.get('vehicleRecommendationService');
const getBookingService = () => container.get('bookingService');
const getBookingStatusService = () => container.get('bookingStatusService');
const getGuestBookingLookupService = () => container.get('guestBookingLookupService');

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

const lookupGuestBooking = asyncHandler(async (req, res) => {
  const data = await getGuestBookingLookupService().lookup(req.body);
  return success(res, data, 'Booking found');
});

module.exports = {
  recommendVehicle,
  createBooking,
  updateBookingStatus,
  issueDropoffQr,
  lookupGuestBooking,
};
