const Joi = require('joi');
const { registerSchema } = require('./auth.validator');

const updateCustomerProfileSchema = Joi.object({
  name: registerSchema.extract('name'),
  phone: registerSchema.extract('phone'),
  phoneCountryCode: Joi.string().trim().max(5).allow('', null).optional(),
});

module.exports = {
  updateCustomerProfileSchema,
};
