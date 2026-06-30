const Joi = require('joi');

const locationUpdateSchema = Joi.object({
  latitude: Joi.number().min(-90).max(90).required(),
  longitude: Joi.number().min(-180).max(180).required(),
  accuracyMeters: Joi.number().min(0).max(5000).allow(null),
  heading: Joi.number().min(0).max(359).allow(null),
  speedKph: Joi.number().min(0).max(240).allow(null),
  recordedAt: Joi.string().isoDate().allow(null),
});

const adminDriverLocationQuerySchema = Joi.object({
  onlineOnly: Joi.boolean().truthy('true').falsy('false').default(false),
  activeJobOnly: Joi.boolean().truthy('true').falsy('false').default(false),
  staleOnly: Joi.boolean().truthy('true').falsy('false').default(false),
});

const bookingIdParamsSchema = Joi.object({
  bookingId: Joi.number().integer().positive().required(),
});

module.exports = {
  locationUpdateSchema,
  adminDriverLocationQuerySchema,
  bookingIdParamsSchema,
};
