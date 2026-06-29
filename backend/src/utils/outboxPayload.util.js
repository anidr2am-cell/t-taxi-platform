const { EVENTS } = require('../events');

const FORBIDDEN_OUTBOX_KEYS = new Set([
  'guestAccessToken',
  'guest_access_token',
  'token',
  'token_hash',
  'qrToken',
  'qr_token',
  'boardingQrToken',
  'dropoffQrToken',
  'password',
  'accessToken',
  'refreshToken',
  'filePath',
  'file_path',
  'commission_receipt_file_id',
  'receiptFileId',
]);

const NOTIFICATION_OUTBOX_EVENTS = new Set([
  EVENTS.BOOKING_CREATED,
  EVENTS.BOOKING_CONFIRMED,
  EVENTS.DRIVER_ASSIGNED,
  EVENTS.DRIVER_REASSIGNED,
  EVENTS.DRIVER_ARRIVED,
  EVENTS.TRIP_PICKED_UP,
  EVENTS.TRIP_COMPLETED,
  EVENTS.COMMISSION_REQUIRED,
  EVENTS.RECEIPT_SUBMITTED,
  EVENTS.RECEIPT_REJECTED,
  EVENTS.SETTLEMENT_APPROVED,
  EVENTS.REVIEW_SUBMITTED,
  EVENTS.CHAT_MESSAGE_SENT,
  EVENTS.FLIGHT_DELAYED,
  EVENTS.FLIGHT_CANCELLED,
  EVENTS.FLIGHT_LANDED,
]);

function sanitizeOutboxPayload(payload) {
  const safe = {};
  for (const [key, value] of Object.entries(payload ?? {})) {
    if (FORBIDDEN_OUTBOX_KEYS.has(key)) continue;
    if (value == null) continue;
    if (typeof value === 'string' && value.length > 500) continue;
    safe[key] = value;
  }
  return safe;
}

function isNotificationOutboxEvent(eventType) {
  return NOTIFICATION_OUTBOX_EVENTS.has(eventType);
}

module.exports = {
  FORBIDDEN_OUTBOX_KEYS,
  NOTIFICATION_OUTBOX_EVENTS,
  sanitizeOutboxPayload,
  isNotificationOutboxEvent,
};
