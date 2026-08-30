const Joi = require('joi');
const CONTACT_CHANNEL = require('../constants/contactChannel');
const { bookingNumberParam } = require('./common.validator');

const bookingNumberParamsSchema = Joi.object({
  bookingNumber: bookingNumberParam.required(),
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
