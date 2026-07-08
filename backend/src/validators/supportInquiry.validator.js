const Joi = require('joi');
const SupportInquiryService = require('../services/supportInquiry.service');

const localeValues = ['ko', 'en', 'th', 'ja', 'zh'];
const statusValues = SupportInquiryService.STATUS_VALUES;

const createSupportInquirySchema = Joi.object({
  message: Joi.string().trim().min(1).max(5000).required(),
  customerName: Joi.string().trim().max(100).allow('', null),
  customerPhone: Joi.string().trim().max(30).allow('', null),
  customerEmail: Joi.string().trim().lowercase().email().max(255).empty('').optional(),
  kakaoId: Joi.string().trim().max(100).allow('', null),
  lineId: Joi.string().trim().max(100).allow('', null),
  locale: Joi.string().valid(...localeValues).allow('', null),
});

const publicSupportInquiryParamsSchema = Joi.object({
  publicId: Joi.string().trim().max(32).required(),
});

const publicSupportInquiryLookupSchema = Joi.object({
  token: Joi.string().trim().max(200).allow('', null),
});

const adminSupportInquiryListQuerySchema = Joi.object({
  page: Joi.number().integer().min(1).optional(),
  page_size: Joi.number().integer().min(1).max(100).optional(),
  limit: Joi.number().integer().min(1).max(100).optional(),
  status: Joi.string().valid(...statusValues).optional(),
  search: Joi.string().trim().max(100).allow('', null),
});

const adminSupportInquiryIdParamsSchema = Joi.object({
  id: Joi.number().integer().positive().required(),
});

const adminSupportInquiryAttachmentParamsSchema = Joi.object({
  id: Joi.number().integer().positive().required(),
  attachmentId: Joi.number().integer().positive().required(),
});

const adminSupportInquiryStatusSchema = Joi.object({
  status: Joi.string().valid(...statusValues).required(),
});

const supportInquiryMessageSchema = Joi.object({
  message: Joi.string().trim().min(1).max(5000).required(),
});

module.exports = {
  createSupportInquirySchema,
  publicSupportInquiryParamsSchema,
  publicSupportInquiryLookupSchema,
  adminSupportInquiryListQuerySchema,
  adminSupportInquiryIdParamsSchema,
  adminSupportInquiryAttachmentParamsSchema,
  adminSupportInquiryStatusSchema,
  supportInquiryMessageSchema,
};
