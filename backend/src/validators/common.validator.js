/**
 * validators/common.validator.js — Shared Joi pieces
 */
const Joi = require("joi");

const CONTROL_CHARACTER_PATTERN =
  /[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/u;
const VEHICLE_PLATE_PATTERN = /^[\p{L}\p{M}\p{N} -]+$/u;
const API_DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;

function normalizeUnicodeTextValue(value, helpers) {
  if (value == null) return value;
  const normalized = String(value).normalize("NFC").trim();
  if (CONTROL_CHARACTER_PATTERN.test(normalized)) {
    return helpers.error("string.controlCharacters");
  }
  return normalized;
}

function unicodeText({ min = 1, max = 100, allowEmpty = false } = {}) {
  let schema = Joi.string()
    .custom(normalizeUnicodeTextValue)
    .max(max)
    .messages({
      "string.controlCharacters":
        "{{#label}} contains unsupported control characters",
    });

  if (allowEmpty) {
    schema = schema.allow(null).empty("").optional();
  } else {
    schema = schema.min(min).required();
  }

  return schema;
}

function normalizeVehiclePlateValue(value, helpers) {
  const normalized = normalizeUnicodeTextValue(value, helpers);
  if (typeof normalized !== "string") return normalized;
  const compact = normalized.replace(/\s+/gu, " ");
  if (!VEHICLE_PLATE_PATTERN.test(compact)) {
    return helpers.error("string.vehiclePlate");
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
      "string.controlCharacters":
        "{{#label}} contains unsupported control characters",
      "string.vehiclePlate":
        "{{#label}} may contain letters, numbers, spaces, and hyphens",
    });
}

const paginationQuery = Joi.object({
  page: Joi.number().integer().min(1).default(1),
  page_size: Joi.number().integer().min(1).max(100).default(20),
});

function isRealApiDate(value) {
  if (typeof value !== "string" || !API_DATE_PATTERN.test(value)) return false;
  const [year, month, day] = value.split("-").map(Number);
  const date = new Date(Date.UTC(year, month - 1, day));
  return (
    date.getUTCFullYear() === year &&
    date.getUTCMonth() === month - 1 &&
    date.getUTCDate() === day
  );
}

function apiDate() {
  return Joi.string()
    .pattern(API_DATE_PATTERN)
    .custom((value, helpers) => {
      if (!isRealApiDate(value)) return helpers.error("date.format");
      return value;
    })
    .messages({
      "string.pattern.base": "{{#label}} must use YYYY-MM-DD format",
      "date.format": "{{#label}} must be a real YYYY-MM-DD date",
    });
}

const bookingNumberParam = Joi.string().pattern(/^TX[0-9]{12}$/);

module.exports = {
  apiDate,
  isRealApiDate,
  paginationQuery,
  bookingNumberParam,
  unicodeText,
  vehiclePlateText,
};
