const Joi = require('joi');
const { unicodeText } = require('./common.validator');

const customerSearchQuerySchema = Joi.object({
  query: Joi.string().trim().min(1).max(100).required(),
});

const recentCustomersQuerySchema = Joi.object({
  limit: Joi.number().integer().min(1).max(50).default(20),
});

const issueCouponSchema = Joi.object({
  customerUserId: Joi.number().integer().positive().required(),
  templateId: Joi.number().integer().positive().optional(),
  title: Joi.when('templateId', {
    is: Joi.exist(),
    then: unicodeText({ max: 255 }).optional(),
    otherwise: unicodeText({ max: 255 }).required(),
  }),
  discountAmount: Joi.when('templateId', {
    is: Joi.exist(),
    then: Joi.number().integer().min(1).optional(),
    otherwise: Joi.number().integer().min(1).required(),
  }),
});

const couponIdParamSchema = Joi.object({
  id: Joi.number().integer().positive().required(),
});

const adminCouponListQuerySchema = Joi.object({
  limit: Joi.number().integer().min(1).max(100).default(20),
});

const createTemplateSchema = Joi.object({
  title: unicodeText({ max: 255 }).required(),
  discountAmount: Joi.number().integer().min(1).required(),
});

const updateTemplateSchema = Joi.object({
  isActive: Joi.boolean().required(),
});

module.exports = {
  customerSearchQuerySchema,
  recentCustomersQuerySchema,
  issueCouponSchema,
  couponIdParamSchema,
  adminCouponListQuerySchema,
  createTemplateSchema,
  updateTemplateSchema,
};
