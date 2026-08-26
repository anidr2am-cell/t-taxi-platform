const asyncHandler = require('../utils/asyncHandler');
const { success } = require('../utils/apiResponse');
const container = require('../helpers/container');

const getBookingService = () => container.get('bookingService');

const claimBooking = asyncHandler(async (req, res) => {
  const data = await getBookingService().claimBookingWithGuestToken({
    userId: req.user.id,
    bookingNumber: req.body.bookingNumber,
    guestAccessToken: req.body.guestAccessToken,
  });
  return success(res, data, 'Booking linked to your account');
});

module.exports = {
  claimBooking,
};
