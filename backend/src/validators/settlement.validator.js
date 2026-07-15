const Joi = require('joi');
const { paginationQuery, bookingNumberParam, unicodeText } = require('./common.validator');

const bookingNumberParamsSchema = Joi.object({
  bookingNumber: bookingNumberParam.required(),
});

const adminSettlementListQuerySchema = paginationQuery.keys({
  page_size: Joi.number().integer().min(1).max(100).optional(),
  limit: Joi.number().integer().min(1).max(100).optional(),
  status: Joi.string()
    .valid('PENDING', 'RECEIPT_SUBMITTED', 'APPROVED', 'REJECTED', 'OVERDUE')
    .optional(),
  driverId: Joi.number().integer().positive().optional(),
  bookingNumber: Joi.string().max(20).optional(),
  completedDateFrom: Joi.string().pattern(/^\d{4}-\d{2}-\d{2}$/).optional(),
  completedDateTo: Joi.string().pattern(/^\d{4}-\d{2}-\d{2}$/).optional(),
  overdueOnly: Joi.boolean().truthy('true').falsy('false').optional(),
});

const settlementRejectSchema = Joi.object({
  reason: unicodeText({ max: 500 }),
});

const settlementManualApproveSchema = Joi.object({
  note: unicodeText({ max: 500 }),
});

module.exports = {
  bookingNumberParamsSchema,
  adminSettlementListQuerySchema,
  settlementRejectSchema,
  settlementManualApproveSchema,
};
