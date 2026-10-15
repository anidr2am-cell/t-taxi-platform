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
const Joi = require('joi');
const container = require('../helpers/container');
const asyncHandler = require('../utils/asyncHandler');
const { success } = require('../utils/apiResponse');
const adminOnly = [authMiddleware, roleMiddleware([ROLES.ADMIN, ROLES.SUPER_ADMIN])];

router.get('/notifications/email-review', adminOnly,
  validate({ query: Joi.object({ includeHandled: Joi.boolean().optional(), page: Joi.number().integer().min(1).max(100000).optional() }) }),
  asyncHandler(async (req, res) => success(res, await container.get('notificationService').listEmailReviews(req.query))));
router.get('/notifications/email-review/:deliveryId', adminOnly,
  validate({ params: Joi.object({ deliveryId: Joi.number().integer().positive().required() }) }),
  asyncHandler(async (req, res) => success(res, await container.get('notificationRepository').emailAttemptHistory(Number(req.params.deliveryId)))));
router.post('/notifications/email-review/:deliveryId', adminOnly,
  validate({ params: Joi.object({ deliveryId: Joi.number().integer().positive().required() }),
    body: Joi.object({ action: Joi.string().valid('RETRY_APPROVED','ACCEPTED_CONFIRMED','HANDLED_EXTERNALLY','KEEP_BLOCKED').required(),
      reason: Joi.string().trim().min(3).max(1000).required(),
      expectedAttemptId: Joi.number().integer().positive().when('action', { is: 'RETRY_APPROVED', then: Joi.required(), otherwise: Joi.forbidden() }) }) }),
  asyncHandler(async (req, res) => success(res, await container.get('notificationService').reviewEmailDelivery(Number(req.params.deliveryId), req.body, req.user))));

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
