const asyncHandler = require('../utils/asyncHandler');
const { success } = require('../utils/apiResponse');
const container = require('../helpers/container');

const getDriverJobService = () => container.get('driverJobService');
const getDriverQrService = () => container.get('driverQrService');

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

const markArrived = asyncHandler(async (req, res) => {
  const data = await getDriverQrService().markArrived(
    req.user.id,
    req.params.bookingNumber,
  );
  return success(res, data, 'OK');
});

const scanBoarding = asyncHandler(async (req, res) => {
  const data = await getDriverQrService().scanBoarding(
    req.user.id,
    req.params.bookingNumber,
    req.body?.token,
  );
  return success(res, data, 'OK');
});

const scanDropoff = asyncHandler(async (req, res) => {
  const data = await getDriverQrService().scanDropoff(
    req.user.id,
    req.params.bookingNumber,
    req.body?.token,
  );
  return success(res, data, 'OK');
});

module.exports = {
  listTodayBookings,
  getBookingDetail,
  markArrived,
  scanBoarding,
  scanDropoff,
};
