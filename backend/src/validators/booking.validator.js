/**
 * validators/booking.validator.js — Skeleton (implement with OpenAPI BookingRequest)
 */
const Joi = require('joi');
const { SERVICE_TYPES } = require('../constants/serviceTypes');
const { VEHICLE_TYPES } = require('../constants/vehicleTypes');

// TODO: expand to match OpenAPI BookingRequest schema
const createBookingSchema = Joi.object({
  serviceTypeCode: Joi.string().valid(...Object.values(SERVICE_TYPES)).required(),
  vehicleTypeCode: Joi.string().valid(...Object.values(VEHICLE_TYPES)).required(),
  customer: Joi.object({
    name: Joi.string().required(),
    email: Joi.string().email().required(),
    phone: Joi.string().required(),
  }).required(),
});

module.exports = {
  createBookingSchema,
};
