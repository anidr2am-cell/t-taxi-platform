import { io } from 'socket.io-client';
import crypto from 'node:crypto';
import { createRequire } from 'node:module';
import { pathToFileURL } from 'node:url';

const BACKEND_ROOT = (process.env.SOCKET_BACKEND_ROOT || '/srv/tride/backend').replace(/\\/g, '/');
const requireBackend = createRequire(pathToFileURL(`${BACKEND_ROOT}/package.json`).href);
const { pool } = requireBackend('./src/config/database');
const { buildUrgentBookingBody } = requireBackend('./urgent-booking-body.cjs');
const { bookingHttpErrorReport } = requireBackend('./urgent-qa-http-report.cjs');
const { fetchUrgentDbMarkers } = requireBackend('./urgent-qa-db-markers.cjs');
const { formatFatalRunnerError } = requireBackend('./urgent-qa-db-errors.cjs');
const { loginDriverApi } = requireBackend('./qa-ui-driver-auth.cjs');

const ORIGIN = (process.env.QA_SOCKET_ORIGIN || 'http://127.0.0.1:3000').replace(/\/$/, '');
const API = `${ORIGIN}/api/v1`;
const CUSTOMER_JWT = process.env.QA_CUSTOMER_JWT;
const DRIVER_PHONE = process.env.QA_SOCKET_DRIVER_PHONE || '1111111002';

const report = {
  executedAt: new Date().toISOString(),
  scope: 'urgent_gate_false_smoke',
  cases: {},
  pass: false,
};

function fail(id, detail) {
  report.cases[id] = { ok: false, ...detail };
  throw new Error(`case_${id}`);
}

function ok(id, detail) {
  report.cases[id] = { ok: true, ...detail };
}

async function dbUrgentMarkers(bookingNumber) {
  return fetchUrgentDbMarkers(pool, bookingNumber, {
    includeNegotiation: false,
    includeMetadata: false,
  });
}

try {
  const login = await loginDriverApi(API, DRIVER_PHONE);
  report.driverLogin = { httpStatus: login.httpStatus, errorCode: login.errorCode, loginPass: login.loginOk };
  if (!login.loginOk || !login.accessToken) {
    fail('UF-login', { httpStatus: login.httpStatus, errorCode: login.errorCode });
  }
  ok('UF-login', { httpStatus: login.httpStatus, loginPass: true });

  if (!CUSTOMER_JWT) fail('UF', { reason: 'missing_customer_jwt' });

  const events = [];
  const socket = io(ORIGIN, { transports: ['websocket', 'polling'], auth: { token: login.accessToken } });
  await new Promise((resolve, reject) => {
    const t = setTimeout(() => reject(new Error('connect_timeout')), 15000);
    socket.once('connect', () => { clearTimeout(t); resolve(); });
    socket.once('connect_error', reject);
  });
  socket.on('driver:urgent-call:new', (p) => {
    events.push({ bookingNumber: p?.bookingNumber, event: 'driver:urgent-call:new' });
  });

  const res = await fetch(`${API}/bookings`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${CUSTOMER_JWT}`,
      'Content-Type': 'application/json',
      'Idempotency-Key': crypto.randomUUID(),
    },
    body: JSON.stringify(buildUrgentBookingBody(80, 'gate-false')),
  });
  const json = await res.json().catch(() => ({}));
  if (res.status !== 201) {
    fail('UF', { create: bookingHttpErrorReport(res.status, json) });
  }
  const bn = json.data?.bookingNumber;
  if (json.data?.contactStatus !== 'VERIFIED') {
    fail('UF', { reason: 'expected_verified_contact_at_create', contactStatus: json.data?.contactStatus });
  }

  await new Promise((r) => setTimeout(r, 1800));
  socket.close();

  const received = events.filter((e) => e.bookingNumber === bn);
  const db = await dbUrgentMarkers(bn);
  if (received.length < 1) fail('UF', { clientUrgentReceives: received.length, db });
  if (db?.urgentNotificationRows < 1) fail('UF', { reason: 'no_urgent_notifications', db });

  ok('UF', {
    bookingNumber: bn,
    clientUrgentReceives: received.length,
    db,
    note: 'gate=false immediate urgent broadcast',
  });

  report.pass = Object.values(report.cases).every((c) => c.ok);
} catch (e) {
  report.pass = false;
  if (!Object.keys(report.cases).length) {
    report.fatal = formatFatalRunnerError(e, 'gate_false_smoke');
  }
}

console.log(JSON.stringify(report, null, 2));
await pool.end();
process.exit(report.pass ? 0 : 1);
