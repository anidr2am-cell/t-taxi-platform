const asyncHandler = require('../utils/asyncHandler');
const { success, paginate } = require('../utils/apiResponse');
const container = require('../helpers/container');

const getAdminDispatchService = () => container.get('adminDispatchService');

const listBookings = asyncHandler(async (req, res) => {
  const data = await getAdminDispatchService().listBookings(req.query);
  return paginate(res, {
    page: data.page,
    pageSize: data.pageSize,
    total: data.total,
    items: data.items,
  });
});

const getBookingDetail = asyncHandler(async (req, res) => {
  const data = await getAdminDispatchService().getBookingDetail(req.params.bookingNumber);
  return success(res, data);
});

const listDrivers = asyncHandler(async (req, res) => {
  const data = await getAdminDispatchService().listDrivers();
  return success(res, data);
});

const assignDriver = asyncHandler(async (req, res) => {
  const data = await getAdminDispatchService().assignDriver(
    req.params.bookingNumber,
    req.body,
    req.user,
  );
  return success(res, data, 'Driver assigned');
});

const reassignDriver = asyncHandler(async (req, res) => {
  const data = await getAdminDispatchService().reassignDriver(
    req.params.bookingNumber,
    req.body,
    req.user,
  );
  return success(res, data, 'Driver reassigned');
});

module.exports = {
  listBookings,
  getBookingDetail,
  listDrivers,
  assignDriver,
  reassignDriver,
};
