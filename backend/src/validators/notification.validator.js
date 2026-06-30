const Joi = require('joi');
const { paginationQuery } = require('./common.validator');

const notificationListQuerySchema = paginationQuery.keys({
  page_size: Joi.number().integer().min(1).max(100).optional(),
  limit: Joi.number().integer().min(1).max(100).optional(),
  unreadOnly: Joi.boolean().optional(),
  notificationType: Joi.string().max(50).optional(),
  createdFrom: Joi.string().pattern(/^\d{4}-\d{2}-\d{2}$/).optional(),
  createdTo: Joi.string().pattern(/^\d{4}-\d{2}-\d{2}$/).optional(),
});

const notificationDeliveryListQuerySchema = notificationListQuerySchema.keys({
  channel: Joi.string().valid('IN_APP', 'EMAIL', 'FCM').optional(),
  deliveryStatus: Joi.string().valid('PENDING', 'DELIVERED', 'SKIPPED', 'FAILED').optional(),
});

const notificationIdParamsSchema = Joi.object({
  notificationId: Joi.number().integer().positive().required(),
});

const notificationDeviceParamsSchema = Joi.object({
  deviceId: Joi.number().integer().positive().required(),
});

const guestNotificationDeviceParamsSchema = Joi.object({
  bookingId: Joi.number().integer().positive().required(),
  deviceId: Joi.number().integer().positive().optional(),
});

const registerNotificationDeviceSchema = Joi.object({
  token: Joi.string()
    .trim()
    .min(20)
    .max(4096)
    .pattern(/^[A-Za-z0-9_:\-./+=]+$/)
    .required(),
  platform: Joi.string().valid('WEB', 'ANDROID', 'IOS').required(),
  deviceName: Joi.string().trim().max(100).allow(null, '').optional(),
  appVersion: Joi.string().trim().max(50).allow(null, '').optional(),
});

module.exports = {
  notificationListQuerySchema,
  notificationDeliveryListQuerySchema,
  notificationIdParamsSchema,
  notificationDeviceParamsSchema,
  guestNotificationDeviceParamsSchema,
  registerNotificationDeviceSchema,
};
