const express = require('express');
const notificationController = require('../controllers/notification.controller');
const validate = require('../middlewares/validate.middleware');
const { authMiddleware } = require('../middlewares/auth.middleware');
const roleMiddleware = require('../middlewares/role.middleware');
const ROLES = require('../constants/roles');
const {
  notificationListQuerySchema,
  notificationDeliveryListQuerySchema,
  notificationIdParamsSchema,
} = require('../validators/notification.validator');

const router = express.Router();
const adminOnly = [authMiddleware, roleMiddleware([ROLES.ADMIN, ROLES.SUPER_ADMIN])];

router.get(
  '/notifications',
  adminOnly,
  validate({ query: notificationListQuerySchema }),
  notificationController.listAdminNotifications,
);

router.get(
  '/notifications/unread-count',
  adminOnly,
  notificationController.adminUnreadCount,
);

router.get(
  '/notifications/deliveries',
  adminOnly,
  validate({ query: notificationDeliveryListQuerySchema }),
  notificationController.listAdminNotificationDeliveries,
);

router.post(
  '/notifications/:notificationId/read',
  adminOnly,
  validate({ params: notificationIdParamsSchema }),
  notificationController.markAdminRead,
);

router.post(
  '/notifications/read-all',
  adminOnly,
  notificationController.markAdminReadAll,
);

module.exports = router;
