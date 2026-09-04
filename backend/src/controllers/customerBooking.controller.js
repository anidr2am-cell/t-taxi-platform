const asyncHandler = require('../utils/asyncHandler');
const { success } = require('../utils/apiResponse');
const container = require('../helpers/container');

const getBookingService = () => container.get('bookingService');
const getCustomerBookingService = () => container.get('customerBookingService');

const claimBooking = asyncHandler(async (req, res) => {
  const data = await getBookingService().claimBookingWithGuestToken({
    userId: req.user.id,
    bookingNumber: req.body.bookingNumber,
    guestAccessToken: req.body.guestAccessToken,
  });
  return success(res, data, 'Booking linked to your account');
});

const listMyBookings = asyncHandler(async (req, res) => {
  const data = await getCustomerBookingService().listMyBookings(req.user.id, req.query);
  return success(res, data);
});

const getBookingStatusCounts = asyncHandler(async (req, res) => {
  const data = await getCustomerBookingService().getBookingStatusCounts(req.user.id);
  return success(res, data);
});

module.exports = {
  claimBooking,
  listMyBookings,
  getBookingStatusCounts,
};
