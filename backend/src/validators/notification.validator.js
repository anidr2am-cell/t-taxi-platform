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

module.exports = {
  notificationListQuerySchema,
  notificationDeliveryListQuerySchema,
  notificationIdParamsSchema,
};
