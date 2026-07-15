const asyncHandler = require('../utils/asyncHandler');
const { success, paginate } = require('../utils/apiResponse');
const container = require('../helpers/container');

const getAdminDispatchService = () => container.get('adminDispatchService');
const getAdminQrReissueService = () => container.get('adminQrReissueService');
const getAdminBookingNoteService = () => container.get('adminBookingNoteService');

const listBookings = asyncHandler(async (req, res) => {
  const data = await getAdminDispatchService().listBookings(req.query, req.user);
  return paginate(res, {
    page: data.page,
    pageSize: data.pageSize,
    total: data.total,
    items: data.items,
    view: data.view,
  });
});

const getBookingsSummary = asyncHandler(async (req, res) => {
  const data = await getAdminDispatchService().getBookingsSummary(req.user);
  return success(res, data);
});

const getBookingDetail = asyncHandler(async (req, res) => {
  const data = await getAdminDispatchService().getBookingDetail(
    req.params.bookingNumber,
    req.user,
  );
  return success(res, data);
});

const listDrivers = asyncHandler(async (req, res) => {
  const data = await getAdminDispatchService().listDrivers(req.query);
  return success(res, data);
});

const archiveDrivers = asyncHandler(async (req, res) => {
  const data = await getAdminDispatchService().archiveDrivers(req.body, req.user);
  return success(res, data, 'Drivers archived');
});

const restoreDriver = asyncHandler(async (req, res) => {
  const data = await getAdminDispatchService().restoreDriver(req.params.id, req.user);
  return success(res, data, 'Driver restored');
});

const getDriverDeletionPreview = asyncHandler(async (req, res) => {
  const data = await getAdminDispatchService().getDriverDeletionPreview(req.params.id);
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

const getDriverCandidates = asyncHandler(async (req, res) => {
  const data = await getAdminDispatchService().getDriverCandidates(req.params.bookingNumber);
  return success(res, data, 'OK');
});

const autoAssignDriver = asyncHandler(async (req, res) => {
  const data = await getAdminDispatchService().autoAssignDriver(
    req.params.bookingNumber,
    req.body,
    req.user,
  );
  return success(res, data, 'Driver assigned');
});

const reissueQr = asyncHandler(async (req, res) => {
  const data = await getAdminQrReissueService().reissueQr(
    req.params.bookingNumber,
    req.body.type,
    req.user,
  );
  return success(res, data, 'QR token reissued');
});

const listBookingNotes = asyncHandler(async (req, res) => {
  const data = await getAdminBookingNoteService().list(
    req.params.bookingNumber,
    req.query,
    req.user,
  );
  return paginate(res, data);
});

const createBookingNote = asyncHandler(async (req, res) => {
  const data = await getAdminBookingNoteService().create(
    req.params.bookingNumber,
    req.body,
    req.user,
  );
  return success(res, data, 'Internal note added', 201);
});

const archiveBookings = asyncHandler(async (req, res) => {
  const data = await getAdminDispatchService().archiveBookings(req.body, req.user);
  return success(res, data, 'Bookings archived');
});

const restoreBookings = asyncHandler(async (req, res) => {
  const data = await getAdminDispatchService().restoreBookings(req.body, req.user);
  return success(res, data, 'Bookings restored');
});

module.exports = {
  listBookings,
  getBookingsSummary,
  getBookingDetail,
  listDrivers,
  archiveDrivers,
  restoreDriver,
  getDriverDeletionPreview,
  assignDriver,
  reassignDriver,
  getDriverCandidates,
  autoAssignDriver,
  reissueQr,
  listBookingNotes,
  createBookingNote,
  archiveBookings,
  restoreBookings,
};
