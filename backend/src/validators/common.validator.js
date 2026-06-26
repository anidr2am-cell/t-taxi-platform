/**
 * validators/common.validator.js — Shared Joi pieces
 */
const Joi = require('joi');

const paginationQuery = Joi.object({
  page: Joi.number().integer().min(1).default(1),
  page_size: Joi.number().integer().min(1).max(100).default(20),
});

const bookingNumberParam = Joi.string().pattern(/^TX[0-9]{14}$/);

module.exports = {
  paginationQuery,
  bookingNumberParam,
};
