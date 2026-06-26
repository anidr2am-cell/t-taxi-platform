const Joi = require('joi');

const localeSchema = Joi.string().valid('ko', 'en', 'th', 'ja', 'zh');

const registerSchema = Joi.object({
  email: Joi.string().trim().lowercase().email().required(),
  password: Joi.string().min(8).max(128).required(),
  name: Joi.string().trim().min(1).max(100).required(),
  phone: Joi.string().trim().min(5).max(30).required(),
  countryCode: Joi.string().trim().uppercase().length(2).optional(),
  locale: localeSchema.optional(),
});

const loginSchema = Joi.object({
  email: Joi.string().trim().lowercase().email().required(),
  password: Joi.string().required(),
});

const refreshSchema = Joi.object({
  refreshToken: Joi.string().trim().required(),
});

const logoutSchema = Joi.object({
  refreshToken: Joi.string().trim().optional(),
});

module.exports = {
  registerSchema,
  loginSchema,
  refreshSchema,
  logoutSchema,
};
