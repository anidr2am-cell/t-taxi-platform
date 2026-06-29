/**
 * validators/booking.validator.js
 */
const Joi = require('joi');
const SERVICE_TYPES = require('../constants/serviceTypes');
const VEHICLE_TYPES = require('../constants/vehicleTypes');
const BOOKING_STATUS = require('../constants/reservationStatus');

const luggageCountField = Joi.number().integer().min(0).default(0);

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
  address: Joi.string().max(500).required(),
  placeId: Joi.string().max(255).allow(null, ''),
  lat: Joi.number().allow(null),
  lng: Joi.number().allow(null),
  name: Joi.string().max(255).allow(null, ''),
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
    specialItems: Joi.string().max(500).allow(null, ''),
    specialLuggageCount: luggageCountField,
  }).default({}),
  options: Joi.object({
    nameSign: Joi.boolean().default(false),
  }).default({}),
  transfer: Joi.object({
    airportIata: Joi.string().length(3).uppercase().allow(null),
    flightNumber: Joi.string().max(20).allow(null, '').custom((value, helpers) => {
      if (value == null || !String(value).trim()) return null;
      const normalized = String(value).trim().replace(/\s+/g, '').toUpperCase();
      if (!/^[A-Z]{2,3}\d{1,4}[A-Z]?$/.test(normalized)) {
        return helpers.error('any.invalid');
      }
      return normalized;
    }).messages({
      'any.invalid': 'Invalid flight number format. Example: TG401',
    }),
    golfCourseId: Joi.number().integer().positive().allow(null),
    golfRegion: Joi.string().max(50).allow(null, ''),
    driverIncluded: Joi.boolean().default(false),
  }).default({}),
  customer: Joi.object({
    name: Joi.string().max(100).required(),
    email: Joi.string().email().max(255).required(),
    phone: Joi.string().max(30).required(),
    countryCode: Joi.string().length(2).uppercase().allow(null, ''),
    messengerType: Joi.string().max(30).allow(null, ''),
    messengerId: Joi.string().max(100).allow(null, ''),
  }).required(),
  additionalRequests: Joi.string().max(2000).allow(null, ''),
  specialRequests: Joi.string().max(2000).allow(null, ''),
});

const updateBookingStatusSchema = Joi.object({
  status: Joi.string().valid(...Object.values(BOOKING_STATUS)).required(),
  reason: Joi.string().max(100).allow(null, ''),
  memo: Joi.string().max(500).allow(null, ''),
});

const guestBookingLookupSchema = Joi.object({
  bookingNumber: Joi.string().trim().uppercase().pattern(/^TX\d{12}$/).required(),
  phone: Joi.string().trim().min(4).max(30).required(),
});

module.exports = {
  vehicleRecommendSchema,
  createBookingSchema,
  updateBookingStatusSchema,
  guestBookingLookupSchema,
};
