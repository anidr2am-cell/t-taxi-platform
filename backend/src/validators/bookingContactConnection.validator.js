const Joi = require('joi');
const CONTACT_CHANNEL = require('../constants/contactChannel');

const bookingNumberParamsSchema = Joi.object({
  bookingNumber: Joi.string().trim().uppercase().max(20).required(),
});

const startContactConnectionSchema = Joi.object({
  channel: Joi.string()
    .valid(...Object.values(CONTACT_CHANNEL))
    .required(),
});

module.exports = {
  bookingNumberParamsSchema,
  startContactConnectionSchema,
};
