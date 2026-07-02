/**
 * Service-local datetime helpers.
 *
 * T-Ride stores naive MySQL DATETIME strings as Asia/Bangkok wall-clock values
 * (see BookingService.formatThailandDateTime). Do not parse those with `new Date(str)`.
 */
const SERVICE_TIME_ZONE = 'Asia/Bangkok';
const SERVICE_UTC_OFFSET = '+07:00';
const MYSQL_DATETIME_RE = /^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2}):(\d{2})$/;

function formatMysqlDateTimeFromDate(value) {
  const y = value.getUTCFullYear();
  const mo = String(value.getUTCMonth() + 1).padStart(2, '0');
  const d = String(value.getUTCDate()).padStart(2, '0');
  const h = String(value.getUTCHours()).padStart(2, '0');
  const mi = String(value.getUTCMinutes()).padStart(2, '0');
  const s = String(value.getUTCSeconds()).padStart(2, '0');
  return `${y}-${mo}-${d} ${h}:${mi}:${s}`;
}

/**
 * Parse a service datetime to epoch milliseconds.
 * - `YYYY-MM-DD HH:mm:ss` → Asia/Bangkok wall clock
 * - ISO-8601 strings → native Date.parse semantics
 * - mysql2 Date values → digits reinterpreted as Bangkok wall clock
 *
 * @returns {number|null} epoch ms, or null when value is missing/invalid
 */
function parseServiceDateTimeToMs(value) {
  if (value == null || value === '') return null;

  if (value instanceof Date) {
    const ms = value.getTime();
    if (Number.isNaN(ms)) return null;
    return parseServiceDateTimeToMs(formatMysqlDateTimeFromDate(value));
  }

  const str = String(value).trim();
  if (!str) return null;

  const mysqlMatch = str.match(MYSQL_DATETIME_RE);
  if (mysqlMatch) {
    const isoWithOffset = `${mysqlMatch[1]}-${mysqlMatch[2]}-${mysqlMatch[3]}T${mysqlMatch[4]}:${mysqlMatch[5]}:${mysqlMatch[6]}${SERVICE_UTC_OFFSET}`;
    const ms = Date.parse(isoWithOffset);
    return Number.isNaN(ms) ? null : ms;
  }

  const ms = Date.parse(str);
  return Number.isNaN(ms) ? null : ms;
}

/**
 * @returns {number|null} elapsed milliseconds since value, or null when value is missing/invalid
 */
function getElapsedMsSinceServiceDateTime(value, nowMs = Date.now()) {
  const parsedMs = parseServiceDateTimeToMs(value);
  if (parsedMs == null) return null;
  return nowMs - parsedMs;
}

module.exports = {
  SERVICE_TIME_ZONE,
  SERVICE_UTC_OFFSET,
  parseServiceDateTimeToMs,
  getElapsedMsSinceServiceDateTime,
};
