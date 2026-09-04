const express = require('express');
const notificationController = require('../controllers/notification.controller');
const mileageController = require('../controllers/mileage.controller');
const customerBookingController = require('../controllers/customerBooking.controller');
const validate = require('../middlewares/validate.middleware');
const { authMiddleware } = require('../middlewares/auth.middleware');
const roleMiddleware = require('../middlewares/role.middleware');
const ROLES = require('../constants/roles');
const {
  notificationListQuerySchema,
  notificationIdParamsSchema,
} = require('../validators/notification.validator');
const { claimBookingSchema, customerBookingListQuerySchema } = require('../validators/booking.validator');
const { mileageTransactionListQuerySchema } = require('../validators/mileage.validator');
const {
  customerBookingClaimIpRateLimit,
  customerBookingClaimUserRateLimit,
  customerBookingListIpRateLimit,
  customerBookingListUserRateLimit,
} = require('../middlewares/customerRateLimit.middleware');

const router = express.Router();
const customerOnly = [authMiddleware, roleMiddleware([ROLES.CUSTOMER])];

router.get(
  '/notifications',
  customerOnly,
  validate({ query: notificationListQuerySchema }),
  notificationController.listCustomerNotifications,
);

router.get(
  '/notifications/unread-count',
  customerOnly,
  notificationController.customerUnreadCount,
);

router.post(
  '/notifications/:notificationId/read',
  customerOnly,
  validate({ params: notificationIdParamsSchema }),
  notificationController.markCustomerRead,
);

router.post(
  '/notifications/read-all',
  customerOnly,
  notificationController.markCustomerReadAll,
);

router.get(
  '/mileage',
  customerOnly,
  mileageController.getBalance,
);

router.get(
  '/mileage/transactions',
  customerOnly,
  validate({ query: mileageTransactionListQuerySchema }),
  mileageController.getTransactions,
);

router.get(
  '/bookings/status-counts',
  customerOnly,
  customerBookingController.getBookingStatusCounts,
);

router.get(
  '/bookings',
  customerBookingListIpRateLimit,
  customerOnly,
  customerBookingListUserRateLimit,
  validate({ query: customerBookingListQuerySchema }),
  customerBookingController.listMyBookings,
);

router.post(
  '/bookings/claim',
  customerBookingClaimIpRateLimit,
  customerOnly,
  customerBookingClaimUserRateLimit,
  validate({ body: claimBookingSchema }),
  customerBookingController.claimBooking,
);

module.exports = router;
