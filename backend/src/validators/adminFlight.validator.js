const Joi = require('joi');
const { paginationQuery } = require('./common.validator');
const FLIGHT_STATUS = require('../constants/flightStatus');

const adminFlightListQuerySchema = paginationQuery.keys({
  page_size: Joi.number().integer().min(1).max(100).optional(),
  limit: Joi.number().integer().min(1).max(100).optional(),
  date: Joi.string().pattern(/^\d{4}-\d{2}-\d{2}$/).optional(),
  flightNumber: Joi.string().max(20).optional(),
  status: Joi.string().valid(...Object.values(FLIGHT_STATUS)).optional(),
  delayedOnly: Joi.boolean().truthy('true', '1').falsy('false', '0').optional(),
  bookingNumber: Joi.string().max(20).optional(),
});

const bookingIdParamsSchema = Joi.object({
  bookingId: Joi.number().integer().positive().required(),
});

module.exports = {
  adminFlightListQuerySchema,
  bookingIdParamsSchema,
};
