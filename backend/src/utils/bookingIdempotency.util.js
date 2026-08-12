const crypto = require('node:crypto');

const FINGERPRINT_TOP_LEVEL_FIELDS = [
  'bookingMode',
  'serviceTypeCode',
  'vehicleTypeCode',
  'vehicleCount',
  'scheduledPickupAt',
  'originAirportIata',
  'originLocationCode',
  'destinationLocationCode',
  'destinationRegion',
  'origin',
  'destination',
  'passengers',
  'luggage',
  'options',
  'transfer',
  'customer',
  'additionalRequests',
];

const MAX_IDEMPOTENCY_KEY_LENGTH = 128;
const IDEMPOTENCY_KEY_PATTERN = /^[A-Za-z0-9-]{1,128}$/;

function stableSortValue(value) {
  if (value === null || value === undefined) {
    return value;
  }
  if (Array.isArray(value)) {
    return value.map(stableSortValue);
  }
  if (typeof value !== 'object') {
    return value;
  }
  return Object.keys(value)
    .sort()
    .reduce((acc, key) => {
      acc[key] = stableSortValue(value[key]);
      return acc;
    }, {});
}

function buildBookingCreateFingerprintPayload(input) {
  const payload = {};
  for (const field of FINGERPRINT_TOP_LEVEL_FIELDS) {
    if (input[field] !== undefined) {
      payload[field] = stableSortValue(input[field]);
    }
  }
  return payload;
}

function computeBookingCreateRequestHash(input) {
  const canonical = JSON.stringify(buildBookingCreateFingerprintPayload(input));
  return crypto.createHash('sha256').update(canonical).digest('hex');
}

function normalizeIdempotencyKey(rawValue) {
  if (rawValue === undefined || rawValue === null) {
    return null;
  }
  const value = String(rawValue).trim();
  if (!value) {
    return null;
  }
  if (value.length > MAX_IDEMPOTENCY_KEY_LENGTH || !IDEMPOTENCY_KEY_PATTERN.test(value)) {
    return { invalid: true, value };
  }
  return { invalid: false, value };
}

function getIdempotencyTtlHours() {
  return 72;
}

function computeIdempotencyExpiresAt(now = new Date()) {
  const expiresAt = new Date(now.getTime());
  expiresAt.setUTCHours(expiresAt.getUTCHours() + getIdempotencyTtlHours());
  return expiresAt;
}

module.exports = {
  FINGERPRINT_TOP_LEVEL_FIELDS,
  MAX_IDEMPOTENCY_KEY_LENGTH,
  buildBookingCreateFingerprintPayload,
  computeBookingCreateRequestHash,
  normalizeIdempotencyKey,
  getIdempotencyTtlHours,
  computeIdempotencyExpiresAt,
};
