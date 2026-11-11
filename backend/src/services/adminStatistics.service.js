const AppError = require('../utils/AppError');
const { pool } = require('../config/database');
const callingCodes = new Set(require('../constants/countryCallingCodes.json'));

const DAY = 86400000;
const OPTIONS = ['nameSign', 'femaleDriver', 'golfDriver', 'coupon'];

function parseDate(value) {
  if (typeof value !== 'string' || !/^20\d\d-\d\d-\d\d$/.test(value)) return NaN;
  const ms = Date.parse(value + 'T00:00:00Z');
  return Number.isFinite(ms) && dateKey(ms) === value ? ms : NaN;
}

function dateKey(ms) {
  return new Date(ms).toISOString().slice(0, 10);
}

function dateRange(from, to) {
  const start = parseDate(from);
  const end = parseDate(to);
  if (!Number.isFinite(start) || !Number.isFinite(end) || end < start || end - start >= 366 * DAY) {
    throw new AppError('Choose a valid date range of up to 366 days.', { errorCode: 'STATISTICS_INVALID_RANGE' });
  }
  return { start, end, from, to, until: dateKey(end + DAY) };
}

// libphonenumber calling codes from the same snapshot as the booking picker.
// A shared calling code remains one group. No local subscriber digits leave the API.
function dialCode(hint) {
  const digits = String(hint ?? '').replace(/^(\+|00)/, '');
  for (let length = 1; length <= Math.min(3, digits.length); length++) {
    const prefix = digits.slice(0, length);
    if (callingCodes.has(prefix)) return '+' + prefix;
  }
  return null;
}

function summarize(rows, range) {
  const daily = new Map();
  const monthly = new Map();
  const countries = new Map();
  const flights = new Map();
  const services = new Map();
  const totals = { bookings: 0, passengers: 0, options: {} };

  const add = (map, key, row) => {
    if (!map.has(key)) map.set(key, { key, bookings: 0, passengers: 0, options: {} });
    const entry = map.get(key);
    entry.bookings += Number(row.bookings || 0);
    entry.passengers += Number(row.passengers || 0);
    for (const option of OPTIONS) {
      entry.options[option] = (entry.options[option] || 0) + Number(row[option] || 0);
    }
  };

  for (let ms = range.start; ms <= range.end; ms += DAY) {
    const day = dateKey(ms);
    add(daily, day, {});
    add(monthly, day.slice(0, 7), {});
  }
  const all = new Map([['all', totals]]);
  for (const row of rows) {
    add(daily, row.day, row);
    add(monthly, row.day.slice(0, 7), row);
    add(all, 'all', row);
    add(countries, dialCode(row.phoneHint), row);
    if (row.flight) add(flights, row.flight, row);
    add(services, row.service, row);
  }
  const ranked = map => [...map.values()].sort((a, b) => b.passengers - a.passengers
    || b.bookings - a.bookings || String(a.key).localeCompare(String(b.key)));
  for (const key of OPTIONS) totals.options[key] ??= 0;
  return {
    from: range.from, to: range.to, timezone: 'Asia/Bangkok', totals,
    daily: [...daily.values()], monthly: [...monthly.values()],
    countries: ranked(countries), flights: ranked(flights), services: ranked(services),
  };
}

async function getStatistics(from, to, db = pool) {
  const range = dateRange(from, to);
  // scheduled_pickup_at stores the Bangkok wall time. Use an exclusive upper
  // bound so the predicate can use the booking index and includes the last day.
  const [rows] = await db.query(`
    SELECT day, phoneHint, flight, service, COUNT(*) AS bookings,
      SUM(passengers) AS passengers, SUM(nameSign) AS nameSign,
      SUM(femaleDriver) AS femaleDriver, SUM(golfDriver) AS golfDriver,
      SUM(coupon) AS coupon
    FROM (
      SELECT DATE_FORMAT(b.scheduled_pickup_at, '%Y-%m-%d') AS day,
        CASE
          WHEN TRIM(b.customer_phone) REGEXP '^([+][1-9]|00[1-9])[0-9 ()-]{6,20}$'
          THEN LEFT(REGEXP_REPLACE(TRIM(b.customer_phone), '[^0-9+]', ''), 5)
        END AS phoneHint,
        CASE
          WHEN UPPER(REPLACE(TRIM(t.flight_number), ' ', '')) REGEXP '^[A-Z0-9]{2}[0-9]{1,4}[A-Z]?$'
          THEN UPPER(REPLACE(TRIM(t.flight_number), ' ', ''))
        END AS flight,
        s.code AS service,
        COALESCE(p.adults + p.children + p.infants, 0) AS passengers,
        EXISTS (SELECT 1 FROM booking_charge_items c
          WHERE c.booking_id=b.id AND c.deleted_at IS NULL AND c.charge_type='NAME_SIGN') AS nameSign,
        COALESCE(b.prefer_female_driver, 0) AS femaleDriver,
        CASE WHEN s.code='GOLF_TRANSFER' THEN COALESCE(t.driver_included, 0) ELSE 0 END AS golfDriver,
        EXISTS (SELECT 1 FROM booking_charge_items c
          WHERE c.booking_id=b.id AND c.deleted_at IS NULL AND c.charge_type='COUPON') AS coupon
      FROM bookings b
      JOIN service_types s ON s.id=b.service_type_id
      LEFT JOIN booking_passengers p ON p.booking_id=b.id AND p.deleted_at IS NULL
      LEFT JOIN booking_transfer_details t ON t.booking_id=b.id AND t.deleted_at IS NULL
      WHERE b.status IN ('SETTLEMENT_PENDING', 'COMPLETED')
        AND b.deleted_at IS NULL AND b.is_archived=0
        AND b.scheduled_pickup_at >= ? AND b.scheduled_pickup_at < ?
    ) usage_rows
    GROUP BY day, phoneHint, flight, service
  `, [range.from + ' 00:00:00', range.until + ' 00:00:00']);
  return summarize(rows, range);
}

module.exports = { getStatistics, dateRange, summarize };
