import { io } from 'socket.io-client';
import crypto from 'node:crypto';
import { createRequire } from 'node:module';
import { pathToFileURL } from 'node:url';

const BACKEND_ROOT = (process.env.SOCKET_BACKEND_ROOT || '/srv/tride/backend').replace(/\\/g, '/');
const requireBackend = createRequire(pathToFileURL(`${BACKEND_ROOT}/package.json`).href);
const { pool } = requireBackend('./src/config/database');

const ORIGIN = (process.env.QA_SOCKET_ORIGIN || 'http://127.0.0.1:3000').replace(/\/$/, '');
const API = `${ORIGIN}/api/v1`;
const ADMIN_JWT = process.env.QA_ADMIN_JWT;
const CUSTOMER_JWT = process.env.QA_CUSTOMER_JWT;
const DRIVER_JWT = process.env.QA_DRIVER_JWT;

const report = {
  executedAt: new Date().toISOString(),
  origin: ORIGIN,
  cases: {},
  pass: false,
};

function fail(caseId, detail) {
  report.cases[caseId] = { ok: false, ...detail };
  throw new Error(`case_${caseId}`);
}

function ok(caseId, detail) {
  report.cases[caseId] = { ok: true, ...detail };
}

async function dbMarkers(bookingNumber) {
  const [[b]] = await pool.query(
    `SELECT id, contact_status, status,
            JSON_UNQUOTE(JSON_EXTRACT(metadata, '$.contactDispatchCompleted')) AS dc,
            JSON_UNQUOTE(JSON_EXTRACT(metadata, '$.contactDispatchDelivered')) AS dd
     FROM bookings WHERE booking_number = ? LIMIT 1`,
    [bookingNumber],
  );
  if (!b) return null;
  const [[nc]] = await pool.query(
    'SELECT COUNT(*) c FROM notifications WHERE booking_id = ? AND deleted_at IS NULL',
    [b.id],
  );
  return {
    bookingId: b.id,
    contactStatus: b.contact_status,
    bookingStatus: b.status,
    dispatchCompleted: b.dc,
    dispatchDelivered: b.dd,
    notificationRows: Number(nc.c),
  };
}

// Pickups aligned with socket QA (2029-04 fixture); matrix uses August slots to avoid overlap.
const MATRIX_PICKUPS = {
  1: '2029-08-01T09:00:00+07:00',
  2: '2029-08-02T09:00:00+07:00',
  3: '2029-08-03T09:00:00+07:00',
};

async function seedPendingBooking(suffix) {
  const pickup = MATRIX_PICKUPS[suffix] ?? `2029-08-${String(suffix).padStart(2, '0')}T09:00:00+07:00`;
  const res = await fetch(`${API}/bookings`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${CUSTOMER_JWT}`,
      'Content-Type': 'application/json',
      'Idempotency-Key': crypto.randomUUID(),
    },
    body: JSON.stringify({
      bookingMode: 'STANDARD',
      serviceTypeCode: 'CITY_TRANSFER',
      vehicleTypeCode: 'SEDAN',
      scheduledPickupAt: pickup,
      destinationRegion: 'Matrix QA',
      origin: { name: 'O', address: 'O', placeId: crypto.randomUUID(), lat: 13.7563, lng: 100.5018 },
      destination: { name: 'D', address: 'D', placeId: crypto.randomUUID(), lat: 13.9813, lng: 100.5018 },
      passengers: { adults: 1, children: 0, infants: 0 },
      customer: { name: 'Matrix Cust', phone: '0888333444', email: 'qa-socket@example.com' },
    }),
  });
  const json = await res.json().catch(() => ({}));
  if (res.status !== 201) throw new Error(`create_booking_${res.status}:${JSON.stringify(json.errorCode || json.message || json)}`);
  const bn = json.data?.bookingNumber;
  const guest = json.data?.guestAccessToken;
  await fetch(`${API}/bookings/${bn}/contact-connections`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${CUSTOMER_JWT}`, 'Content-Type': 'application/json', 'x-guest-access-token': guest },
    body: JSON.stringify({ channel: 'LINE' }),
  });
  await fetch(`${API}/bookings/${bn}/contact-connections/confirm-sent`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${CUSTOMER_JWT}`, 'x-guest-access-token': guest },
  });
  return bn;
}

async function verify(bn) {
  const res = await fetch(`${API}/admin/bookings/${bn}/contact/verify`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${ADMIN_JWT}` },
  });
  const json = await res.json().catch(() => ({}));
  return { status: res.status, dispatchStarted: json.data?.dispatchStarted };
}

async function runWithSocket(caseFn) {
  const events = [];
  const socket = io(ORIGIN, { transports: ['websocket', 'polling'], auth: { token: DRIVER_JWT } });
  await new Promise((resolve, reject) => {
    const t = setTimeout(() => reject(new Error('connect_timeout')), 15000);
    socket.once('connect', () => { clearTimeout(t); resolve(); });
    socket.once('connect_error', reject);
  });
  await new Promise((resolve, reject) => {
    socket.emit('driver:calls:subscribe', {}, (ack) => {
      if (!ack?.ok) reject(new Error('subscribe_fail'));
      else resolve(ack);
    });
  });
  socket.on('driver:call:new', (p) => events.push({ at: new Date().toISOString(), bookingNumber: p?.bookingNumber }));
  try {
    await caseFn({ events });
  } finally {
    socket.close();
  }
  return events;
}

try {
  if (!ADMIN_JWT || !CUSTOMER_JWT || !DRIVER_JWT) {
    console.log(JSON.stringify({ ...report, error: 'missing_jwt_env' }));
    process.exit(1);
  }

  await runWithSocket(async ({ events }) => {
    const bn = await seedPendingBooking(1);
    if (events.filter((e) => e.bookingNumber === bn).length > 0) fail('A', { reason: 'event_before_verify' });
    const v1 = await verify(bn);
    if (v1.status !== 200) fail('A', { verifyStatus: v1.status });
    await new Promise((r) => setTimeout(r, 1500));
    const received = events.filter((e) => e.bookingNumber === bn);
    if (received.length !== 1) fail('A', { clientReceives: received.length });
    ok('A', { bookingNumber: bn, clientReceives: 1, db: await dbMarkers(bn) });
  });

  await runWithSocket(async ({ events }) => {
    const bn = await seedPendingBooking(2);
    await verify(bn);
    await new Promise((r) => setTimeout(r, 1500));
    const n1 = events.filter((e) => e.bookingNumber === bn).length;
    if (n1 < 1) fail('B', { reason: 'no_first_socket_receive', clientReceives: n1 });
    const db1 = await dbMarkers(bn);
    await verify(bn);
    await verify(bn);
    await new Promise((r) => setTimeout(r, 1500));
    const n2 = events.filter((e) => e.bookingNumber === bn).length;
    const db2 = await dbMarkers(bn);
    if (n2 !== n1) fail('B', { clientReceivesFirst: n1, clientReceivesAfterRepeat: n2 });
    if (db2 && db1 && db2.notificationRows > db1.notificationRows) {
      fail('B', { reason: 'notification_rows_grew', db1, db2 });
    }
    ok('B', { bookingNumber: bn, clientReceives: n2, db1, db2 });
  });

  await runWithSocket(async ({ events }) => {
    const bn = await seedPendingBooking(3);
    const results = await Promise.all([verify(bn), verify(bn), verify(bn)]);
    await new Promise((r) => setTimeout(r, 2000));
    const n = events.filter((e) => e.bookingNumber === bn).length;
    if (n < 1) fail('C', { reason: 'no_socket_receive', clientReceives: n });
    if (n > 1) fail('C', { clientReceives: n, verifyStatuses: results.map((r) => r.status) });
    ok('C', { bookingNumber: bn, clientReceives: n, verifyStatuses: results.map((r) => r.status), db: await dbMarkers(bn) });
  });

  report.pass = Object.values(report.cases).every((c) => c.ok);
} catch (e) {
  report.pass = false;
  if (!Object.keys(report.cases).length) report.fatal = e.message;
}

console.log(JSON.stringify(report, null, 2));
await pool.end();
process.exit(report.pass ? 0 : 1);
