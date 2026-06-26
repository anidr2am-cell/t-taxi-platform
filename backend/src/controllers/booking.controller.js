const asyncHandler = require('../utils/asyncHandler');
const { success } = require('../utils/apiResponse');
const HTTP_STATUS = require('../constants/httpStatus');
const container = require('../helpers/container');

const getVehicleRecommendationService = () => container.get('vehicleRecommendationService');
const getBookingService = () => container.get('bookingService');

const recommendVehicle = asyncHandler(async (req, res) => {
  const data = await getVehicleRecommendationService().recommend(req.body);
  return success(res, data, data.message);
});

const createBooking = asyncHandler(async (req, res) => {
  const data = await getBookingService().createBooking(req.body, req.user);
  return success(res, data, 'Booking created', HTTP_STATUS.CREATED);
});

module.exports = {
  recommendVehicle,
  createBooking,
};
