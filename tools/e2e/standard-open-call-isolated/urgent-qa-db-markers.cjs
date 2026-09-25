'use strict';

/** Matches NOTIFICATION_TYPES.DRIVER_URGENT_CALL_NEW and persistUrgentCallNotificationsTx insert.type */
const URGENT_NOTIFICATION_TYPE = 'DRIVER_URGENT_CALL_NEW';

/** Prefix in booking.service persistUrgentCallNotificationsTx idempotencyKey */
const URGENT_IDEMPOTENCY_PREFIX = 'driver-urgent-call-new';

const URGENT_RUNNER_SCHEMA_REQUIREMENTS = [
  {
    table: 'bookings',
    columns: [
      'id',
      'booking_number',
      'contact_status',
      'status',
      'is_urgent_request',
      'metadata',
      'urgent_negotiation_id',
    ],
  },
  {
    table: 'notifications',
    columns: ['booking_id', 'type', 'deleted_at', 'idempotency_key'],
  },
  {
    table: 'booking_urgent_negotiations',
    columns: ['id', 'status', 'attempt_count'],
  },
];

async function countUrgentNotifications(pool, bookingId) {
  const [[row]] = await pool.query(
    `SELECT COUNT(*) AS c FROM notifications
     WHERE booking_id = ? AND type = ? AND deleted_at IS NULL`,
    [bookingId, URGENT_NOTIFICATION_TYPE],
  );
  return Number(row.c);
}

async function countUrgentIdempotencyKeys(pool, bookingId) {
  const [[row]] = await pool.query(
    `SELECT COUNT(DISTINCT idempotency_key) AS c FROM notifications
     WHERE booking_id = ? AND type = ? AND deleted_at IS NULL
       AND idempotency_key IS NOT NULL`,
    [bookingId, URGENT_NOTIFICATION_TYPE],
  );
  return Number(row.c);
}

async function loadUrgentBookingMarkers(pool, bookingNumber, options = {}) {
  const includeDispatchMeta = options.includeDispatchMeta ?? options.includeMetadata ?? true;
  const { includeNegotiation = true } = options;
  const selectCols = includeDispatchMeta
    ? `id, contact_status, status, is_urgent_request,
            JSON_UNQUOTE(JSON_EXTRACT(metadata, '$.contactDispatchCompleted')) AS dc,
            JSON_UNQUOTE(JSON_EXTRACT(metadata, '$.contactDispatchDelivered')) AS dd`
    : 'id, contact_status, is_urgent_request';

  const [[b]] = await pool.query(
    `SELECT ${selectCols} FROM bookings WHERE booking_number = ? LIMIT 1`,
    [bookingNumber],
  );
  if (!b) return null;

  const urgentNotificationRows = await countUrgentNotifications(pool, b.id);
  const urgentIdempotencyKeys = await countUrgentIdempotencyKeys(pool, b.id);

  const out = {
    bookingId: b.id,
    contactStatus: b.contact_status,
    isUrgentRequest: Boolean(b.is_urgent_request),
    urgentNotificationRows,
    urgentIdempotencyKeys,
  };

  if (includeDispatchMeta && 'status' in b) {
    out.bookingStatus = b.status;
    out.dispatchCompleted = b.dc;
    out.dispatchDelivered = b.dd;
  }

  if (includeNegotiation) {
    const [[neg]] = await pool.query(
      `SELECT bun.status AS negotiationStatus, bun.attempt_count AS attemptCount
       FROM booking_urgent_negotiations bun
       INNER JOIN bookings bk ON bk.urgent_negotiation_id = bun.id
       WHERE bk.booking_number = ? LIMIT 1`,
      [bookingNumber],
    );
    out.negotiationStatus = neg?.negotiationStatus ?? null;
    out.attemptCount = neg?.attemptCount ?? null;
  }

  return out;
}

/** @deprecated alias for runners */
const fetchUrgentDbMarkers = loadUrgentBookingMarkers;

module.exports = {
  URGENT_NOTIFICATION_TYPE,
  URGENT_IDEMPOTENCY_PREFIX,
  URGENT_RUNNER_SCHEMA_REQUIREMENTS,
  countUrgentNotifications,
  countUrgentIdempotencyKeys,
  loadUrgentBookingMarkers,
  fetchUrgentDbMarkers,
};
