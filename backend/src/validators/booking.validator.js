/**
 * validators/booking.validator.js — Skeleton (implement with OpenAPI BookingRequest)
 */
const Joi = require('joi');
const SERVICE_TYPES = require('../constants/serviceTypes');
const VEHICLE_TYPES = require('../constants/vehicleTypes');

const luggageCountField = Joi.number().integer().min(0).default(0);

const vehicleRecommendSchema = Joi.object({
  adults: Joi.number().integer().min(1).required(),
  children: luggageCountField,
  infants: luggageCountField,
  luggage20: luggageCountField,
  luggage24: luggageCountField,
  golfBags: luggageCountField,
  specialLuggageCount: luggageCountField,
});

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
  vehicleRecommendSchema,
  createBookingSchema,
};
