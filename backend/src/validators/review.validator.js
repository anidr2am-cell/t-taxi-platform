const Joi = require('joi');
const { paginationQuery, bookingNumberParam } = require('./common.validator');

const bookingNumberParamsSchema = Joi.object({
  bookingNumber: bookingNumberParam.required(),
});

const submitReviewSchema = Joi.object({
  rating: Joi.number().integer().min(1).max(5).required(),
  comment: Joi.string().trim().max(500).allow('', null).optional(),
  guestAccessToken: Joi.string().trim().min(1).max(512).optional(),
}).unknown(false);

const reviewIdParamsSchema = Joi.object({
  reviewId: Joi.number().integer().positive().required(),
});

const adminReviewListQuerySchema = paginationQuery.keys({
  page_size: Joi.number().integer().min(1).max(100).optional(),
  limit: Joi.number().integer().min(1).max(100).optional(),
  rating: Joi.number().integer().min(1).max(5).optional(),
  status: Joi.string().valid('VISIBLE', 'HIDDEN').optional(),
  driverId: Joi.number().integer().positive().optional(),
  bookingNumber: Joi.string().max(20).optional(),
  search: Joi.string().trim().max(100).optional(),
  dateFrom: Joi.string().pattern(/^\d{4}-\d{2}-\d{2}$/).optional(),
  dateTo: Joi.string().pattern(/^\d{4}-\d{2}-\d{2}$/).optional(),
});

const reviewHideSchema = Joi.object({
  reason: Joi.string().trim().min(1).max(500).required(),
});

module.exports = {
  bookingNumberParamsSchema,
  submitReviewSchema,
  reviewIdParamsSchema,
  adminReviewListQuerySchema,
  reviewHideSchema,
};
