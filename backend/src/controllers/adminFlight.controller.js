const asyncHandler = require('../utils/asyncHandler');
const { success, paginate } = require('../utils/apiResponse');
const container = require('../helpers/container');

const getAdminFlightMonitorService = () => container.get('adminFlightMonitorService');

const listFlights = asyncHandler(async (req, res) => {
  const data = await getAdminFlightMonitorService().listFlights(req.query);
  return paginate(res, {
    page: data.page,
    pageSize: data.pageSize,
    total: data.total,
    items: data.items,
  });
});

const getFlightDetail = asyncHandler(async (req, res) => {
  const data = await getAdminFlightMonitorService().getFlightDetail(Number(req.params.bookingId));
  return success(res, data);
});

const syncFlight = asyncHandler(async (req, res) => {
  const data = await getAdminFlightMonitorService().syncFlight(Number(req.params.bookingId), req.user);
  return success(res, data, 'Flight synchronized');
});

module.exports = {
  listFlights,
  getFlightDetail,
  syncFlight,
};
