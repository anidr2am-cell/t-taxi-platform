const Joi = require('joi');
const { unicodeText } = require('./common.validator');

const customerSearchQuerySchema = Joi.object({
  query: Joi.string().trim().min(1).max(100).required(),
});

const issueCouponSchema = Joi.object({
  customerUserId: Joi.number().integer().positive().required(),
  title: unicodeText({ max: 255 }).required(),
  discountAmount: Joi.number().integer().min(1).required(),
});

const couponIdParamSchema = Joi.object({
  id: Joi.number().integer().positive().required(),
});

const adminCouponListQuerySchema = Joi.object({
  limit: Joi.number().integer().min(1).max(100).default(20),
});

module.exports = {
  customerSearchQuerySchema,
  issueCouponSchema,
  couponIdParamSchema,
  adminCouponListQuerySchema,
};
