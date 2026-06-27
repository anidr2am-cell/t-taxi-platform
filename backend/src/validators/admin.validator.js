const Joi = require('joi');
const { paginationQuery, bookingNumberParam } = require('./common.validator');
const BOOKING_STATUS = require('../constants/reservationStatus');

const adminBookingListQuerySchema = paginationQuery.keys({
  page_size: Joi.number().integer().min(1).max(100).optional(),
  limit: Joi.number().integer().min(1).max(100).optional(),
  search: Joi.string().max(100).allow('', null),
  status: Joi.string().valid(...Object.values(BOOKING_STATUS)).optional(),
  serviceDateFrom: Joi.string().pattern(/^\d{4}-\d{2}-\d{2}$/).optional(),
  serviceDateTo: Joi.string().pattern(/^\d{4}-\d{2}-\d{2}$/).optional(),
  driverId: Joi.number().integer().positive().optional(),
  assignmentState: Joi.string().valid('ASSIGNED', 'UNASSIGNED').optional(),
  sort: Joi.string().optional(),
});

const bookingNumberParamsSchema = Joi.object({
  bookingNumber: bookingNumberParam.required(),
});

const assignDriverSchema = Joi.object({
  driverId: Joi.number().integer().positive().required(),
  driverVehicleId: Joi.number().integer().positive().optional(),
  assignmentReason: Joi.string().max(255).allow('', null),
  reason: Joi.string().max(255).allow('', null),
});

const reassignDriverSchema = Joi.object({
  driverId: Joi.number().integer().positive().required(),
  driverVehicleId: Joi.number().integer().positive().optional(),
  reason: Joi.string().max(255).required(),
  assignmentReason: Joi.string().max(255).allow('', null),
});

module.exports = {
  adminBookingListQuerySchema,
  bookingNumberParamsSchema,
  assignDriverSchema,
  reassignDriverSchema,
};
