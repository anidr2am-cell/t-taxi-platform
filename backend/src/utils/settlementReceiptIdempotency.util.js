const crypto = require('node:crypto');
const {
  normalizeIdempotencyKey,
  computeIdempotencyExpiresAt,
  getIdempotencyTtlHours,
} = require('./bookingIdempotency.util');

const RECEIPT_UPLOAD_ACTION = 'DRIVER_SETTLEMENT_RECEIPT_UPLOAD';

function hashFileContent(filePath) {
  const buffer = require('node:fs').readFileSync(filePath);
  return crypto.createHash('sha256').update(buffer).digest('hex');
}

function computeSettlementReceiptFingerprint({ bookingId, driverUserId, contentHash }) {
  const canonical = JSON.stringify({
    action: RECEIPT_UPLOAD_ACTION,
    bookingId,
    driverUserId,
    contentHash,
  });
  return crypto.createHash('sha256').update(canonical).digest('hex');
}

function isReceiptIdempotencyKeyRequired(nodeEnv) {
  return nodeEnv === 'production' || nodeEnv === 'staging';
}

module.exports = {
  RECEIPT_UPLOAD_ACTION,
  hashFileContent,
  computeSettlementReceiptFingerprint,
  normalizeIdempotencyKey,
  computeIdempotencyExpiresAt,
  getIdempotencyTtlHours,
  isReceiptIdempotencyKeyRequired,
};
