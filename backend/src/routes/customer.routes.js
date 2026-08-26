const express = require('express');
const notificationController = require('../controllers/notification.controller');
const customerBookingController = require('../controllers/customerBooking.controller');
const validate = require('../middlewares/validate.middleware');
const { authMiddleware } = require('../middlewares/auth.middleware');
const roleMiddleware = require('../middlewares/role.middleware');
const ROLES = require('../constants/roles');
const {
  notificationListQuerySchema,
  notificationIdParamsSchema,
} = require('../validators/notification.validator');
const { claimBookingSchema } = require('../validators/booking.validator');
const {
  customerBookingClaimIpRateLimit,
  customerBookingClaimUserRateLimit,
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

router.post(
  '/bookings/claim',
  customerBookingClaimIpRateLimit,
  customerOnly,
  customerBookingClaimUserRateLimit,
  validate({ body: claimBookingSchema }),
  customerBookingController.claimBooking,
);

module.exports = router;
