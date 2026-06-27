const Joi = require('joi');

const bookingNumberParamsSchema = Joi.object({
  bookingNumber: Joi.string().pattern(/^TX\d{12}$/).required(),
});

const chatMessageListQuerySchema = Joi.object({
  cursor: Joi.number().integer().min(1).optional(),
  limit: Joi.number().integer().min(1).max(100).optional(),
  page_size: Joi.number().integer().min(1).max(100).optional(),
});

const sendChatMessageSchema = Joi.object({
  text: Joi.string().required(),
  clientMessageId: Joi.string().trim().min(8).max(64).required(),
});

const markChatReadSchema = Joi.object({
  upToMessageId: Joi.number().integer().min(1).required(),
  messageId: Joi.number().integer().min(1).optional(),
});

const adminChatListQuerySchema = Joi.object({
  page: Joi.number().integer().min(1).optional(),
  limit: Joi.number().integer().min(1).max(100).optional(),
  page_size: Joi.number().integer().min(1).max(100).optional(),
  search: Joi.string().max(100).allow('').optional(),
  q: Joi.string().max(100).allow('').optional(),
  unreadOnly: Joi.boolean().optional(),
  unread_only: Joi.string().valid('true', 'false').optional(),
});

module.exports = {
  bookingNumberParamsSchema,
  chatMessageListQuerySchema,
  sendChatMessageSchema,
  markChatReadSchema,
  adminChatListQuerySchema,
};
