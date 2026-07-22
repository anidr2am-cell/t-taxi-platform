const asyncHandler = require('../utils/asyncHandler');
const { success } = require('../utils/apiResponse');
const container = require('../helpers/container');

const getDriverJobService = () => container.get('driverJobService');
const getDriverTripFlowService = () => container.get('driverTripFlowService');
const getDriverQrService = () => container.get('driverQrService');
const getDriverStatusService = () => container.get('driverStatusService');
const getDriverCallService = () => container.get('driverCallService');
const getDriverBookingAcceptanceService = () =>
  container.get('driverBookingAcceptanceService');

const listTodayBookings = asyncHandler(async (req, res) => {
  const data = await getDriverJobService().listToday(req.user.id);
  return success(res, data, 'OK');
});

const listScheduledBookings = asyncHandler(async (req, res) => {
  const data = await getDriverJobService().listScheduled(req.user.id);
  return success(res, data, 'OK');
});

const listOpenCalls = asyncHandler(async (req, res) => {
  const data = await getDriverCallService().listOpenCalls(req.user.id);
  return success(res, data, 'OK');
});

const claimOpenCall = asyncHandler(async (req, res) => {
  const data = await getDriverCallService().claimOpenCall(
    req.user.id,
    req.params.bookingNumber,
  );
  return success(res, data, 'OK');
});

const releaseAssignment = asyncHandler(async (req, res) => {
  const data = await getDriverCallService().releaseAssignment(
    req.user.id,
    req.params.bookingNumber,
    req.body || {},
  );
  return success(res, data, 'Assignment released');
});

const acceptBooking = asyncHandler(async (req, res) => {
  const data = await getDriverBookingAcceptanceService().acceptBooking(
    req.user.id,
    req.params.bookingNumber,
  );
  return success(res, data, 'Booking accepted');
});

const getBookingDetail = asyncHandler(async (req, res) => {
  const data = await getDriverJobService().getDetail(
    req.user.id,
    req.params.bookingNumber,
  );
  return success(res, data, 'OK');
});

const startOnRoute = asyncHandler(async (req, res) => {
  const data = await getDriverTripFlowService().startOnRoute(
    req.user.id,
    req.params.bookingNumber,
  );
  return success(res, data, 'OK');
});

const markArrived = asyncHandler(async (req, res) => {
  const data = await getDriverTripFlowService().markArrived(
    req.user.id,
    req.params.bookingNumber,
  );
  return success(res, data, 'OK');
});

const markPickedUp = asyncHandler(async (req, res) => {
  const data = await getDriverTripFlowService().markPickedUp(
    req.user.id,
    req.params.bookingNumber,
  );
  return success(res, data, 'OK');
});

const endTrip = asyncHandler(async (req, res) => {
  const data = await getDriverTripFlowService().endTrip(
    req.user.id,
    req.params.bookingNumber,
  );
  return success(res, data, 'OK');
});

const completeTrip = asyncHandler(async (req, res) => {
  const data = await getDriverTripFlowService().completeTrip(
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

const getStatus = asyncHandler(async (req, res) => {
  const data = await getDriverStatusService().getStatus(req.user.id);
  return success(res, data, 'OK');
});

const goOnline = asyncHandler(async (req, res) => {
  const data = await getDriverStatusService().goOnline(req.user.id);
  return success(res, data, 'OK');
});

const goOffline = asyncHandler(async (req, res) => {
  const data = await getDriverStatusService().goOffline(req.user.id);
  return success(res, data, 'OK');
});

module.exports = {
  listTodayBookings,
  listScheduledBookings,
  listOpenCalls,
  claimOpenCall,
  releaseAssignment,
  acceptBooking,
  getBookingDetail,
  startOnRoute,
  markArrived,
  markPickedUp,
  endTrip,
  completeTrip,
  scanBoarding,
  scanDropoff,
  getStatus,
  goOnline,
  goOffline,
};
