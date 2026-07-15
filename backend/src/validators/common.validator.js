/**
 * validators/common.validator.js — Shared Joi pieces
 */
const Joi = require('joi');

const CONTROL_CHARACTER_PATTERN = /[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/u;
const VEHICLE_PLATE_PATTERN = /^[\p{L}\p{M}\p{N} -]+$/u;

function normalizeUnicodeTextValue(value, helpers) {
  if (value == null) return value;
  const normalized = String(value).normalize('NFC').trim();
  if (CONTROL_CHARACTER_PATTERN.test(normalized)) {
    return helpers.error('string.controlCharacters');
  }
  return normalized;
}

function unicodeText({ min = 1, max = 100, allowEmpty = false } = {}) {
  let schema = Joi.string()
    .custom(normalizeUnicodeTextValue)
    .max(max)
    .messages({
      'string.controlCharacters': '{{#label}} contains unsupported control characters',
    });

  if (allowEmpty) {
    schema = schema.allow(null).empty('').optional();
  } else {
    schema = schema.min(min).required();
  }

  return schema;
}

function normalizeVehiclePlateValue(value, helpers) {
  const normalized = normalizeUnicodeTextValue(value, helpers);
  if (typeof normalized !== 'string') return normalized;
  const compact = normalized.replace(/\s+/gu, ' ');
  if (!VEHICLE_PLATE_PATTERN.test(compact)) {
    return helpers.error('string.vehiclePlate');
  }
  return compact;
}

function vehiclePlateText({ min = 1, max = 30 } = {}) {
  return Joi.string()
    .custom(normalizeVehiclePlateValue)
    .min(min)
    .max(max)
    .required()
    .messages({
      'string.controlCharacters': '{{#label}} contains unsupported control characters',
      'string.vehiclePlate': '{{#label}} may contain letters, numbers, spaces, and hyphens',
    });
}

const paginationQuery = Joi.object({
  page: Joi.number().integer().min(1).default(1),
  page_size: Joi.number().integer().min(1).max(100).default(20),
});

const bookingNumberParam = Joi.string().pattern(/^TX[0-9]{12}$/);

module.exports = {
  paginationQuery,
  bookingNumberParam,
  unicodeText,
  vehiclePlateText,
};
