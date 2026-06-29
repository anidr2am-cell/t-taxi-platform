const asyncHandler = require('../utils/asyncHandler');
const { success, paginate } = require('../utils/apiResponse');
const container = require('../helpers/container');
const { extractGuestAccessTokenFromHeader } = require('../utils/guestAccess.util');

const getNotificationService = () => container.get('notificationService');

const listCustomerNotifications = asyncHandler(async (req, res) => {
  const data = await getNotificationService().listForUser(
    req.user.id,
    req.user.role,
    req.query,
  );
  return paginate(res, {
    page: data.page,
    pageSize: data.pageSize,
    total: data.total,
    items: data.items,
  });
});

const customerUnreadCount = asyncHandler(async (req, res) => {
  const data = await getNotificationService().unreadCountForUser(req.user.id, req.user.role);
  return success(res, data);
});

const markCustomerRead = asyncHandler(async (req, res) => {
  const data = await getNotificationService().markReadForUser(
    req.user.id,
    req.user.role,
    Number(req.params.notificationId),
  );
  return success(res, data);
});

const markCustomerReadAll = asyncHandler(async (req, res) => {
  const data = await getNotificationService().markAllReadForUser(req.user.id, req.user.role);
  return success(res, data);
});

const listBookingNotifications = asyncHandler(async (req, res) => {
  const data = await getNotificationService().getBookingNotifications(
    req.params.bookingNumber,
    req.user ?? null,
    extractGuestAccessTokenFromHeader(req),
    req.query,
  );
  return paginate(res, {
    page: data.page,
    pageSize: data.pageSize,
    total: data.total,
    items: data.items,
  });
});

const listDriverNotifications = asyncHandler(async (req, res) => {
  const data = await getNotificationService().listForUser(
    req.user.id,
    req.user.role,
    req.query,
  );
  return paginate(res, {
    page: data.page,
    pageSize: data.pageSize,
    total: data.total,
    items: data.items,
  });
});

const driverUnreadCount = asyncHandler(async (req, res) => {
  const data = await getNotificationService().unreadCountForUser(req.user.id, req.user.role);
  return success(res, data);
});

const markDriverRead = asyncHandler(async (req, res) => {
  const data = await getNotificationService().markReadForUser(
    req.user.id,
    req.user.role,
    Number(req.params.notificationId),
  );
  return success(res, data);
});

const markDriverReadAll = asyncHandler(async (req, res) => {
  const data = await getNotificationService().markAllReadForUser(req.user.id, req.user.role);
  return success(res, data);
});

const listAdminNotifications = asyncHandler(async (req, res) => {
  const data = await getNotificationService().listForUser(
    req.user.id,
    req.user.role,
    req.query,
  );
  return paginate(res, {
    page: data.page,
    pageSize: data.pageSize,
    total: data.total,
    items: data.items,
  });
});

const listAdminNotificationDeliveries = asyncHandler(async (req, res) => {
  const data = await getNotificationService().listDeliveryStatuses(req.query);
  return paginate(res, {
    page: data.page,
    pageSize: data.pageSize,
    total: data.total,
    items: data.items,
  });
});

const adminUnreadCount = asyncHandler(async (req, res) => {
  const data = await getNotificationService().unreadCountForUser(req.user.id, req.user.role);
  return success(res, data);
});

const markAdminRead = asyncHandler(async (req, res) => {
  const data = await getNotificationService().markReadForUser(
    req.user.id,
    req.user.role,
    Number(req.params.notificationId),
  );
  return success(res, data);
});

const markAdminReadAll = asyncHandler(async (req, res) => {
  const data = await getNotificationService().markAllReadForUser(req.user.id, req.user.role);
  return success(res, data);
});

module.exports = {
  listCustomerNotifications,
  customerUnreadCount,
  markCustomerRead,
  markCustomerReadAll,
  listBookingNotifications,
  listDriverNotifications,
  driverUnreadCount,
  markDriverRead,
  markDriverReadAll,
  listAdminNotifications,
  listAdminNotificationDeliveries,
  adminUnreadCount,
  markAdminRead,
  markAdminReadAll,
};
