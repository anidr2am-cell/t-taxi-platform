const asyncHandler = require('../utils/asyncHandler');
const { success } = require('../utils/apiResponse');
const container = require('../helpers/container');
const { extractGuestAccessTokenFromHeader } = require('../utils/guestAccess.util');

const getDriverLocationService = () => container.get('driverLocationService');

const updateDriverLocation = asyncHandler(async (req, res) => {
  const data = await getDriverLocationService().updateDriverLocation(req.user.id, req.body);
  return success(res, {
    accepted: data.accepted,
    recordedAt: data.recordedAt,
    reason: data.reason,
  });
});

const listAdminDriverLocations = asyncHandler(async (req, res) => {
  const data = await getDriverLocationService().listAdminLocations(req.query);
  return success(res, data);
});

const getGuestDriverLocation = asyncHandler(async (req, res) => {
  const data = await getDriverLocationService().getGuestDriverLocation(
    Number(req.params.bookingId),
    extractGuestAccessTokenFromHeader(req),
  );
  return success(res, data);
});

module.exports = {
  updateDriverLocation,
  listAdminDriverLocations,
  getGuestDriverLocation,
};
