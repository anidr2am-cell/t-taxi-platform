import { io } from 'socket.io-client';
import crypto from 'node:crypto';
import { createRequire } from 'node:module';
import { pathToFileURL } from 'node:url';

const BACKEND_ROOT = (process.env.SOCKET_BACKEND_ROOT || '/srv/tride/backend').replace(/\\/g, '/');
const requireBackend = createRequire(pathToFileURL(`${BACKEND_ROOT}/package.json`).href);
const { pool } = requireBackend('./src/config/database');
const { buildUrgentBookingBody } = requireBackend('./urgent-booking-body.cjs');
const { formatBookingCreateFailure } = requireBackend('./urgent-qa-http-report.cjs');
const { fetchUrgentDbMarkers } = requireBackend('./urgent-qa-db-markers.cjs');
const { formatFatalRunnerError } = requireBackend('./urgent-qa-db-errors.cjs');

const ORIGIN = (process.env.QA_SOCKET_ORIGIN || 'http://127.0.0.1:3000').replace(/\/$/, '');
const API = `${ORIGIN}/api/v1`;
const ADMIN_JWT = process.env.QA_ADMIN_JWT;
const CUSTOMER_JWT = process.env.QA_CUSTOMER_JWT;
const DRIVER_JWT = process.env.QA_DRIVER_JWT;
const DRIVER_LOGIN_HTTP = process.env.QA_DRIVER_LOGIN_HTTP_STATUS
  ? Number(process.env.QA_DRIVER_LOGIN_HTTP_STATUS)
  : null;

const report = {
  executedAt: new Date().toISOString(),
  scope: 'urgent_contact_dispatch_gate_true',
  origin: ORIGIN,
  driverAuth: {
    mode: process.env.QA_DRIVER_AUTH_MODE || 'login_or_env',
    loginHttpStatus: DRIVER_LOGIN_HTTP,
  },
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

async function dbUrgentMarkers(bookingNumber) {
  return fetchUrgentDbMarkers(pool, bookingNumber, {
    includeNegotiation: true,
    includeMetadata: true,
  });
}

async function seedUrgentAwaitingVerify(minutesFromNow) {
  const res = await fetch(`${API}/bookings`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${CUSTOMER_JWT}`,
      'Content-Type': 'application/json',
      'Idempotency-Key': crypto.randomUUID(),
    },
    body: JSON.stringify(buildUrgentBookingBody(minutesFromNow, `matrix-${minutesFromNow}`)),
  });
  const json = await res.json().catch(() => ({}));
  if (res.status !== 201) {
    throw new Error(formatBookingCreateFailure(res.status, json));
  }
  const bn = json.data?.bookingNumber;
  const guest = json.data?.guestAccessToken;
  const contactStatus = json.data?.contactStatus;
  await fetch(`${API}/bookings/${bn}/contact-connections`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${CUSTOMER_JWT}`,
      'Content-Type': 'application/json',
      'x-guest-access-token': guest,
    },
    body: JSON.stringify({ channel: 'LINE' }),
  });
  await fetch(`${API}/bookings/${bn}/contact-connections/confirm-sent`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${CUSTOMER_JWT}`, 'x-guest-access-token': guest },
  });
  return { bn, contactStatusAtCreate: contactStatus };
}

async function verify(bn) {
  const res = await fetch(`${API}/admin/bookings/${bn}/contact/verify`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${ADMIN_JWT}` },
  });
  const json = await res.json().catch(() => ({}));
  return { status: res.status, errorCode: json.errorCode ?? null, dispatchStarted: json.data?.dispatchStarted };
}

function urgentEvents(events, bn) {
  return events.filter((e) => e.event === 'driver:urgent-call:new' && e.bookingNumber === bn);
}

async function runWithUrgentSocket(caseFn) {
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
  socket.on('driver:urgent-call:new', (p) => {
    events.push({
      at: new Date().toISOString(),
      event: 'driver:urgent-call:new',
      bookingNumber: p?.bookingNumber,
    });
  });
  socket.on('driver:call:new', (p) => {
    events.push({
      at: new Date().toISOString(),
      event: 'driver:call:new',
      bookingNumber: p?.bookingNumber,
    });
  });
  try {
    await caseFn({ events, socket });
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

  // UA: before admin verify — no urgent broadcast to drivers
  await runWithUrgentSocket(async ({ events }) => {
    const { bn } = await seedUrgentAwaitingVerify(50);
    await new Promise((r) => setTimeout(r, 1200));
    const received = urgentEvents(events, bn);
    const db = await dbUrgentMarkers(bn);
    if (received.length > 0) fail('UA', { clientUrgentReceives: received.length });
    if (db?.contactStatus !== 'CONFIRM_REQUESTED') {
      fail('UA', { reason: 'unexpected_contact_status', db });
    }
    if (db?.urgentNotificationRows > 0) {
      fail('UA', { reason: 'urgent_notifications_before_verify', db });
    }
    ok('UA', {
      bookingNumber: bn,
      clientUrgentReceives: 0,
      db,
      note: 'CONFIRM_REQUESTED only — dispatch deferred',
    });
  });

  // UB: admin verify starts urgent dispatch once
  await runWithUrgentSocket(async ({ events }) => {
    const { bn } = await seedUrgentAwaitingVerify(55);
    const v1 = await verify(bn);
    if (v1.status !== 200) fail('UB', { verifyStatus: v1.status, errorCode: v1.errorCode });
    await new Promise((r) => setTimeout(r, 1800));
    const received = urgentEvents(events, bn);
    const db = await dbUrgentMarkers(bn);
    if (received.length !== 1) fail('UB', { clientUrgentReceives: received.length, verify: v1 });
    if (db?.contactStatus !== 'VERIFIED') fail('UB', { reason: 'not_verified', db });
    if (db?.negotiationStatus !== 'BROADCASTING') fail('UB', { reason: 'negotiation_not_broadcasting', db });
    if (db?.urgentNotificationRows < 1) fail('UB', { reason: 'no_urgent_notification_rows', db });
    ok('UB', {
      bookingNumber: bn,
      verifyHttp: v1.status,
      dispatchStarted: v1.dispatchStarted,
      clientUrgentReceives: received.length,
      db,
    });
  });

  // UC: confirm-sent only (never verify) — still blocked
  await runWithUrgentSocket(async ({ events }) => {
    const { bn } = await seedUrgentAwaitingVerify(60);
    await new Promise((r) => setTimeout(r, 1500));
    const mid = urgentEvents(events, bn).length;
    if (mid > 0) fail('UC', { clientUrgentReceives: mid });
    ok('UC', {
      bookingNumber: bn,
      clientUrgentReceives: 0,
      db: await dbUrgentMarkers(bn),
      note: 'confirm-sent without admin verify',
    });
  });

  // UD: sequential repeat verify — no duplicate socket / notification growth
  await runWithUrgentSocket(async ({ events }) => {
    const { bn } = await seedUrgentAwaitingVerify(65);
    await verify(bn);
    await new Promise((r) => setTimeout(r, 1500));
    const n1 = urgentEvents(events, bn).length;
    const db1 = await dbUrgentMarkers(bn);
    await verify(bn);
    await verify(bn);
    await new Promise((r) => setTimeout(r, 1500));
    const n2 = urgentEvents(events, bn).length;
    const db2 = await dbUrgentMarkers(bn);
    if (n2 !== n1) fail('UD', { clientReceivesFirst: n1, clientReceivesAfterRepeat: n2 });
    if (db2 && db1 && db2.urgentNotificationRows > db1.urgentNotificationRows) {
      fail('UD', { reason: 'urgent_notification_rows_grew', db1, db2 });
    }
    if (db2 && db1 && db2.urgentIdempotencyKeys > db1.urgentIdempotencyKeys) {
      fail('UD', { reason: 'urgent_idempotency_keys_grew', db1, db2 });
    }
    ok('UD', { bookingNumber: bn, clientUrgentReceives: n2, db1, db2 });
  });

  // UE: concurrent verify — at most one urgent socket receive
  await runWithUrgentSocket(async ({ events }) => {
    const { bn } = await seedUrgentAwaitingVerify(70);
    const results = await Promise.all([verify(bn), verify(bn), verify(bn)]);
    await new Promise((r) => setTimeout(r, 2000));
    const n = urgentEvents(events, bn).length;
    if (n < 1) fail('UE', { reason: 'no_socket_receive', clientUrgentReceives: n });
    if (n > 1) {
      fail('UE', { clientUrgentReceives: n, verifyStatuses: results.map((r) => r.status) });
    }
    ok('UE', {
      bookingNumber: bn,
      clientUrgentReceives: n,
      verifyStatuses: results.map((r) => r.status),
      db: await dbUrgentMarkers(bn),
    });
  });

  report.pass = Object.values(report.cases).every((c) => c.ok);
} catch (e) {
  report.pass = false;
  if (!Object.keys(report.cases).length) {
    report.fatal = formatFatalRunnerError(e, 'gate_true_matrix');
  }
}

console.log(JSON.stringify(report, null, 2));
await pool.end();
process.exit(report.pass ? 0 : 1);
