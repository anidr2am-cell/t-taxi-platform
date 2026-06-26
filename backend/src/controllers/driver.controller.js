const asyncHandler = require('../utils/asyncHandler');
const { success } = require('../utils/apiResponse');
const container = require('../helpers/container');

const getDriverJobService = () => container.get('driverJobService');

const listTodayBookings = asyncHandler(async (req, res) => {
  const data = await getDriverJobService().listToday(req.user.id);
  return success(res, data, 'OK');
});

const getBookingDetail = asyncHandler(async (req, res) => {
  const data = await getDriverJobService().getDetail(
    req.user.id,
    req.params.bookingNumber,
  );
  return success(res, data, 'OK');
});

module.exports = {
  listTodayBookings,
  getBookingDetail,
};
