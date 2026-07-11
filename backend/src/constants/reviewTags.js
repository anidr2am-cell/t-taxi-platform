const AppError = require('../utils/AppError');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');

const POSITIVE_TAGS = [
  'FRIENDLY',
  'SAFE_DRIVING',
  'CLEAN_VEHICLE',
  'ON_TIME',
  'GOOD_COMMUNICATION',
];

const NEGATIVE_TAGS = [
  'UNSAFE_DRIVING',
  'LATE_ARRIVAL',
  'VEHICLE_NOT_CLEAN',
  'UNFRIENDLY_SERVICE',
  'ROUTE_ISSUE',
  'OTHER_ISSUE',
];

const POSITIVE_TAG_SET = new Set(POSITIVE_TAGS);
const NEGATIVE_TAG_SET = new Set(NEGATIVE_TAGS);
const ALL_TAGS = new Set([...POSITIVE_TAGS, ...NEGATIVE_TAGS]);

function allowedTagsForRating(rating) {
  if (rating <= 2) {
    return ALL_TAGS;
  }
  return POSITIVE_TAG_SET;
}

function normalizeTags(input, rating) {
  if (input == null) return [];
  if (!Array.isArray(input)) {
    throw new AppError('Tags must be an array', {
      statusCode: HTTP_STATUS.BAD_REQUEST,
      errorCode: ERROR_CODES.VALIDATION_ERROR,
    });
  }

  const allowed = allowedTagsForRating(rating);
  const normalized = [];
  const seen = new Set();

  for (const raw of input) {
    const code = String(raw ?? '').trim().toUpperCase();
    if (!code) continue;
    if (!ALL_TAGS.has(code)) {
      throw new AppError('Review tag is not allowed', {
        statusCode: HTTP_STATUS.BAD_REQUEST,
        errorCode: ERROR_CODES.VALIDATION_ERROR,
        errors: [{ tag: code }],
      });
    }
    if (!allowed.has(code)) {
      throw new AppError('Review tag is not allowed for this rating', {
        statusCode: HTTP_STATUS.BAD_REQUEST,
        errorCode: ERROR_CODES.VALIDATION_ERROR,
        errors: [{ tag: code, rating }],
      });
    }
    if (seen.has(code)) continue;
    seen.add(code);
    normalized.push(code);
  }

  return normalized;
}

function parseStoredTags(value) {
  if (value == null || value === '') return [];
  if (Array.isArray(value)) {
    return value
      .map((item) => String(item).trim().toUpperCase())
      .filter((item) => ALL_TAGS.has(item));
  }
  if (typeof value === 'string') {
    try {
      const parsed = JSON.parse(value);
      return parseStoredTags(parsed);
    } catch (_err) {
      return [];
    }
  }
  if (typeof value === 'object') {
    return [];
  }
  return [];
}

module.exports = {
  POSITIVE_TAGS,
  NEGATIVE_TAGS,
  ALL_TAGS,
  allowedTagsForRating,
  normalizeTags,
  parseStoredTags,
};
