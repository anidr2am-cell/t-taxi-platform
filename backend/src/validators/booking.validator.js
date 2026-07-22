/**
 * validators/booking.validator.js
 */
const Joi = require('joi');
const SERVICE_TYPES = require('../constants/serviceTypes');
const VEHICLE_TYPES = require('../constants/vehicleTypes');
const BOOKING_STATUS = require('../constants/reservationStatus');
const { unicodeText } = require('./common.validator');
const {
  FLIGHT_NUMBER_INVALID_MESSAGE,
  isValidFlightNumber,
  normalizeFlightNumber,
} = require('../utils/flightNumber.util');

const luggageCountField = Joi.number().integer().min(0).default(0);

function normalizeOptionalEmail(value) {
  if (value == null) return null;
  const normalized = String(value).trim();
  return normalized || null;
}

const optionalEmailField = Joi.string().max(255).allow(null, '').custom((value, helpers) => {
  const normalized = normalizeOptionalEmail(value);
  if (normalized == null) return null;
  const { error } = Joi.string().email().validate(normalized);
  if (error) return helpers.error('string.email');
  return normalized;
}).default(null);

function normalizeOptionalCountry(value) {
  if (value == null) return null;
  const normalized = String(value).trim();
  return normalized || null;
}

const optionalCountryField = Joi.string()
  .trim()
  .max(100)
  .allow(null)
  .empty('')
  .custom((value) => normalizeOptionalCountry(value))
  .default(null);

function validateScheduledPickupAt(value, helpers) {
  const timestamp = Date.parse(value);
  if (Number.isNaN(timestamp)) {
    return helpers.error('date.format');
  }

  const minimum = Date.now() + (2 * 60 * 60 * 1000);
  if (timestamp < minimum) {
    return helpers.message('scheduledPickupAt must be at least 2 hours from now');
  }

  return value;
}

const vehicleRecommendSchema = Joi.object({
  adults: Joi.number().integer().min(1).required(),
  children: luggageCountField,
  infants: luggageCountField,
  luggage20: luggageCountField,
  luggage24: luggageCountField,
  golfBags: luggageCountField,
  specialLuggageCount: luggageCountField,
});

const placeSchema = Joi.object({
  address: unicodeText({ max: 500 }),
  placeId: Joi.string().max(255).allow(null, ''),
  lat: Joi.number().allow(null),
  lng: Joi.number().allow(null),
  name: unicodeText({ max: 255, allowEmpty: true }).default(null),
});

const createBookingSchema = Joi.object({
  serviceTypeCode: Joi.string().valid(...Object.values(SERVICE_TYPES)).required(),
  vehicleTypeCode: Joi.string().valid(...Object.values(VEHICLE_TYPES)).required(),
  vehicleCount: Joi.number().integer().min(1).max(5).default(1),
  scheduledPickupAt: Joi.string().isoDate().required().custom(validateScheduledPickupAt),
  origin: placeSchema.required(),
  destination: placeSchema.required(),
  originAirportIata: Joi.string().length(3).uppercase().allow(null),
  destinationRegion: Joi.string().max(100).allow(null, ''),
  originLocationCode: Joi.string().max(50).allow(null, ''),
  destinationLocationCode: Joi.string().max(50).allow(null, ''),
  destinationAirportIata: Joi.string().length(3).uppercase().allow(null),
  passengers: Joi.object({
    adults: Joi.number().integer().min(1).required(),
    children: luggageCountField,
    infants: luggageCountField,
  }).required(),
  luggage: Joi.object({
    carriers20Inch: luggageCountField,
    carriers24InchPlus: luggageCountField,
    golfBags: luggageCountField,
    specialItems: unicodeText({ max: 500, allowEmpty: true }).default(null),
    specialLuggageCount: luggageCountField,
  }).default({}),
  options: Joi.object({
    nameSign: Joi.boolean().default(false),
  }).default({}),
  transfer: Joi.object({
    airportIata: Joi.string().length(3).uppercase().allow(null),
    flightNumber: Joi.string().max(20).allow(null).empty('').custom((value, helpers) => {
      const normalized = normalizeFlightNumber(value);
      if (normalized == null) return null;
      if (!isValidFlightNumber(normalized)) {
        return helpers.error('any.invalid');
      }
      return normalized;
    }).default(null).messages({
      'any.invalid': FLIGHT_NUMBER_INVALID_MESSAGE,
    }),
    golfCourseId: Joi.number().integer().positive().allow(null),
    golfRegion: Joi.string().max(50).allow(null, ''),
    driverIncluded: Joi.boolean().default(false),
  }).default({}),
  customer: Joi.object({
    name: unicodeText({ max: 100 }),
    email: optionalEmailField,
    phone: Joi.string().max(30).required(),
    countryCode: optionalCountryField,
    messengerType: Joi.string().max(30).allow(null, ''),
    messengerId: Joi.string().max(100).allow(null, ''),
  }).required(),
  additionalRequests: unicodeText({ max: 2000, allowEmpty: true }).default(null),
  specialRequests: unicodeText({ max: 2000, allowEmpty: true }).default(null),
});

const updateBookingStatusSchema = Joi.object({
  status: Joi.string().valid(...Object.values(BOOKING_STATUS)).required(),
  reason: unicodeText({ max: 100, allowEmpty: true }).default(null),
  memo: unicodeText({ max: 500, allowEmpty: true }).default(null),
});

const cancelBookingSchema = Joi.object({
  guestAccessToken: Joi.string().trim().min(1).max(512).optional(),
  reason: unicodeText({ max: 100, allowEmpty: true }).default(null),
  memo: unicodeText({ max: 500, allowEmpty: true }).default(null),
});

const guestBookingLookupSchema = Joi.object({
  bookingNumber: Joi.string().trim().uppercase().pattern(/^TX\d{12}$/).required(),
  phone: Joi.string().trim().min(4).max(30).required(),
});

module.exports = {
  vehicleRecommendSchema,
  createBookingSchema,
  updateBookingStatusSchema,
  cancelBookingSchema,
  guestBookingLookupSchema,
  normalizeOptionalEmail,
  normalizeOptionalCountry,
};
