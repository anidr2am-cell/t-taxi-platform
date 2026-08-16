#!/usr/bin/env node
/**
 * Staging LIVE E2E: URGENT timeout worker hardening (Phase 3 Step 4).
 * Uses production APIs for setup/teardown and real UrgentNegotiationService
 * timeout processors with injected nowMs (no sleep, no expiry timestamp edits).
 */
const fs = require('node:fs');
const path = require('node:path');
const { createBookingSchema } = require('../src/validators/booking.validator');
const { parseServiceDateTimeToMs } = require('../src/utils/serviceDateTime.util');
const {
  assertSafeEnvironment,
  toPricingPayload,
  createBookingIdempotencyKey,
  REGRESSION_MARKER,
  TEST_NAME_PREFIX,
} = require('./staging-booking-regression');
const {
  assertTestDriverEligibleForNewJob,
  cleanupRegressionBooking,
  formatCleanupFailure,
} = require('./e2eRegressionCleanup');

const CUSTOMER_NAME = `${TEST_NAME_PREFIX} Urgent Timeout Hardening`;
const ETA_MINUTES = 42;
const TIMEOUT_MS = Number(process.env.TRIDE_REGRESSION_TIMEOUT_MS || 25000);
const PREFERRED_CHANNELS = ['LINE', 'WHATSAPP', 'KAKAO'];

function loadE2eLocalEnv() {
  const candidates = [
    path.resolve(__dirname, '../../.env.e2e.local'),
    '/srv/tride/.env.e2e.local',
  ];
  const filePath = candidates.find((candidate) => fs.existsSync(candidate));
  if (!filePath) return;
  for (const line of fs.readFileSync(filePath, 'utf8').split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const index = trimmed.indexOf('=');
    if (index < 0) continue;
    const key = trimmed.slice(0, index).trim();
    let value = trimmed.slice(index + 1).trim();
    if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
      value = value.slice(1, -1);
    }
    if (process.env[key] == null || process.env[key] === '') {
      process.env[key] = value;
    }
  }
  if (!process.env.TRIDE_BASE_URL && process.env.TRIDE_E2E_BACKEND_URL) {
    process.env.TRIDE_BASE_URL = process.env.TRIDE_E2E_BACKEND_URL;
  }
  if (!process.env.TRIDE_ADMIN_EMAIL && process.env.TRIDE_E2E_ADMIN_EMAIL) {
    process.env.TRIDE_ADMIN_EMAIL = process.env.TRIDE_E2E_ADMIN_EMAIL;
  }
  if (!process.env.TRIDE_ADMIN_PASSWORD && process.env.TRIDE_E2E_ADMIN_PASSWORD) {
    process.env.TRIDE_ADMIN_PASSWORD = process.env.TRIDE_E2E_ADMIN_PASSWORD;
  }
  if (!process.env.TRIDE_TEST_DRIVER_EMAIL && process.env.TRIDE_E2E_DRIVER_EMAIL) {
    process.env.TRIDE_TEST_DRIVER_EMAIL = process.env.TRIDE_E2E_DRIVER_EMAIL;
  }
  if (!process.env.TRIDE_TEST_DRIVER_PASSWORD && process.env.TRIDE_E2E_DRIVER_PASSWORD) {
    process.env.TRIDE_TEST_DRIVER_PASSWORD = process.env.TRIDE_E2E_DRIVER_PASSWORD;
  }
  if (!process.env.TRIDE_ALLOW_LIVE_BOOKING_REGRESSION) {
    process.env.TRIDE_ALLOW_LIVE_BOOKING_REGRESSION = '1';
  }
}

function urgentPickup(offsetMinutes = 120) {
  return new Date(Date.now() + offsetMinutes * 60 * 1000).toISOString();
}

function bookingPayload() {
  return {
    bookingMode: 'URGENT',
    serviceTypeCode: 'AIRPORT_PICKUP',
    vehicleTypeCode: 'SUV',
    vehicleCount: 1,
    scheduledPickupAt: urgentPickup(),
    origin: {
      name: 'Suvarnabhumi Airport',
      address: 'Suvarnabhumi Airport, Bangkok, Thailand',
      placeId: 'staging-bkk-timeout-e2e',
    },
    destination: {
      name: 'Pattaya',
      address: 'Pattaya, Chon Buri, Thailand',
      placeId: 'staging-pattaya-timeout-e2e',
    },
    originAirportIata: 'BKK',
    destinationLocationCode: 'PATTAYA',
    transfer: { airportIata: 'BKK', flightNumber: 'TG404' },
    passengers: { adults: 2, children: 0, infants: 0 },
    luggage: { carriers20Inch: 1, carriers24InchPlus: 0, golfBags: 0 },
    options: { nameSign: true, nameSignText: 'E2E Timeout' },
    customer: {
      name: CUSTOMER_NAME,
      phone: '+66000000005',
      email: 'urgent-timeout-hardening-e2e@example.com',
      countryCode: 'TH',
    },
    additionalRequests: REGRESSION_MARKER,
  };
}

function responseData(body) {
  return body?.data ?? body;
}

function expiredNowMs(timestamp) {
  const expiresMs = parseServiceDateTimeToMs(timestamp);
  if (expiresMs == null) {
    throw new Error(`Invalid expiry timestamp: ${timestamp}`);
  }
  return expiresMs + 60_000;
}

function workerConfigReport() {
  return {
    URGENT_NEGOTIATION_TIMEOUT_ENABLED: process.env.URGENT_NEGOTIATION_TIMEOUT_ENABLED ?? '(unset)',
    URGENT_NEGOTIATION_TIMEOUT_INTERVAL_MS: process.env.URGENT_NEGOTIATION_TIMEOUT_INTERVAL_MS ?? '(unset)',
    URGENT_NEGOTIATION_TIMEOUT_BATCH_SIZE: process.env.URGENT_NEGOTIATION_TIMEOUT_BATCH_SIZE ?? '(unset)',
  };
}

async function fetchJson(baseUrl, urlPath, options = {}) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);
  try {
    const response = await fetch(`${baseUrl}${urlPath}`, {
      ...options,
      headers: {
        'content-type': 'application/json',
        ...(options.headers || {}),
      },
      signal: controller.signal,
    });
    const text = await response.text();
    const body = text ? JSON.parse(text) : null;
    return { ok: response.ok, status: response.status, body };
  } finally {
    clearTimeout(timer);
  }
}

async function login(baseUrl, email, password) {
  const { ok, body } = await fetchJson(baseUrl, '/api/v1/auth/login', {
    method: 'POST',
    body: JSON.stringify({ email, password }),
  });
  if (!ok) throw new Error(`Login failed: ${body?.error_code || body?.message}`);
  const token = body?.data?.accessToken || body?.data?.access_token;
  if (!token) throw new Error('Login missing access token');
  return { token, user: body?.data?.user ?? null };
}

function guestHeaders(guestAccessToken) {
  return { 'x-guest-access-token': guestAccessToken };
}

function pickEnabledContactChannel(channelsPayload) {
  const channels = Array.isArray(channelsPayload?.channels) ? channelsPayload.channels : [];
  for (const code of PREFERRED_CHANNELS) {
    const match = channels.find((row) => row.code === code && row.enabled);
    if (match) return code;
  }
  const fallback = channels.find((row) => row.enabled);
  if (!fallback) throw new Error('No enabled contact channel');
  return fallback.code;
}

async function verifyContactFlow(baseUrl, { bookingNumber, guestAccessToken, adminToken }) {
  const channelsBody = responseData((await fetchJson(baseUrl, '/api/v1/bookings/contact-channels/public')).body);
  const channel = pickEnabledContactChannel(channelsBody);
  await fetchJson(baseUrl, `/api/v1/bookings/${bookingNumber}/contact-connections`, {
    method: 'POST',
    headers: guestHeaders(guestAccessToken),
    body: JSON.stringify({ channel }),
  });
  await fetchJson(baseUrl, `/api/v1/bookings/${bookingNumber}/contact-connections/confirm-sent`, {
    method: 'POST',
    headers: guestHeaders(guestAccessToken),
  });
  const verify = await fetchJson(
    baseUrl,
    `/api/v1/admin/bookings/${bookingNumber}/contact/verify`,
    {
      method: 'POST',
      headers: { authorization: `Bearer ${adminToken}` },
    },
  );
  if (!verify.ok) throw new Error(`Admin verify failed: ${verify.body?.error_code}`);
  if (responseData(verify.body)?.contactStatus !== 'VERIFIED') {
    throw new Error('Contact not VERIFIED after admin verify');
  }
}

async function createUrgentBooking(baseUrl, payload) {
  await fetchJson(baseUrl, '/api/v1/bookings/pricing/calculate', {
    method: 'POST',
    body: JSON.stringify(toPricingPayload(payload)),
  });
  const created = await fetchJson(baseUrl, '/api/v1/bookings', {
    method: 'POST',
    headers: { 'Idempotency-Key': createBookingIdempotencyKey() },
    body: JSON.stringify(payload),
  });
  if (!created.ok) throw new Error(`Create booking failed: ${created.body?.error_code}`);
  const createdData = responseData(created.body);
  if (!createdData?.isUrgentRequest && createdData?.bookingMode !== 'URGENT') {
    throw new Error('Created booking is not urgent');
  }
  return createdData;
}

async function lockUrgentCall(baseUrl, driverToken, bookingNumber) {
  return fetchJson(baseUrl, `/api/v1/driver/urgent-calls/${bookingNumber}/lock`, {
    method: 'POST',
    headers: { authorization: `Bearer ${driverToken}` },
    body: JSON.stringify({}),
  });
}

async function submitUrgentEta(baseUrl, driverToken, bookingNumber, etaMinutes) {
  return fetchJson(baseUrl, `/api/v1/driver/urgent-calls/${bookingNumber}/eta`, {
    method: 'POST',
    headers: { authorization: `Bearer ${driverToken}` },
    body: JSON.stringify({ etaMinutes }),
  });
}

async function submitUrgentDecision(baseUrl, bookingNumber, decision, guestAccessToken) {
  return fetchJson(baseUrl, `/api/v1/bookings/${bookingNumber}/urgent-decision`, {
    method: 'POST',
    headers: guestHeaders(guestAccessToken),
    body: JSON.stringify({ decision }),
  });
}

async function fetchUrgentNegotiation(baseUrl, bookingNumber, guestAccessToken) {
  const response = await fetchJson(baseUrl, `/api/v1/bookings/${bookingNumber}/urgent-negotiation`, {
    headers: guestHeaders(guestAccessToken),
  });
  if (!response.ok) throw new Error(`Urgent negotiation fetch failed: ${response.body?.error_code}`);
  return responseData(response.body);
}

async function adminUnassign(baseUrl, adminToken, bookingNumber) {
  return fetchJson(baseUrl, `/api/v1/admin/bookings/${bookingNumber}/unassign-driver`, {
    method: 'POST',
    headers: { authorization: `Bearer ${adminToken}` },
    body: JSON.stringify({ reason: REGRESSION_MARKER }),
  });
}

async function getUrgentNegotiationService() {
  const container = require('../src/helpers/container');
  return container.get('urgentNegotiationService');
}

async function getDbPool() {
  const database = require('../src/config/database');
  return database.pool;
}

async function fetchDbSnapshot(pool, bookingNumber, negotiationId = null) {
  const [bookingRows] = await pool.query(
    `
      SELECT
        b.booking_number,
        b.status AS booking_status,
        b.urgent_negotiation_id AS current_negotiation_id
      FROM bookings b
      WHERE b.booking_number = ?
        AND b.deleted_at IS NULL
      LIMIT 1
    `,
    [bookingNumber],
  );
  const booking = bookingRows[0] ?? null;
  const targetNegotiationId = negotiationId ?? booking?.current_negotiation_id ?? null;
  let negotiation = null;
  let latestAttemptOutcome = null;
  let activeAssignmentCount = 0;
  let latestAssignmentStatus = null;
  let latestAssignmentReason = null;

  if (targetNegotiationId) {
    const [negRows] = await pool.query(
      `
        SELECT id, status AS negotiation_status, attempt_count, locked_driver_id
        FROM booking_urgent_negotiations
        WHERE id = ?
        LIMIT 1
      `,
      [targetNegotiationId],
    );
    negotiation = negRows[0] ?? null;
    if (negotiation) {
      const [attemptRows] = await pool.query(
        `
          SELECT outcome
          FROM booking_urgent_negotiation_attempts
          WHERE negotiation_id = ?
          ORDER BY attempt_number DESC
          LIMIT 1
        `,
        [targetNegotiationId],
      );
      latestAttemptOutcome = attemptRows[0]?.outcome ?? null;
    }
  }

  if (booking) {
    const [assignmentCountRows] = await pool.query(
      `
        SELECT COUNT(*) AS active_assignment_count
        FROM booking_driver_assignments bda
        WHERE bda.booking_id = (
          SELECT id FROM bookings WHERE booking_number = ? AND deleted_at IS NULL LIMIT 1
        )
          AND bda.is_active = 1
          AND bda.deleted_at IS NULL
      `,
      [bookingNumber],
    );
    activeAssignmentCount = Number(assignmentCountRows[0]?.active_assignment_count ?? 0);

    const [assignmentRows] = await pool.query(
      `
        SELECT bda.status, bda.assignment_reason
        FROM booking_driver_assignments bda
        INNER JOIN bookings b ON b.id = bda.booking_id
        WHERE b.booking_number = ?
          AND bda.deleted_at IS NULL
        ORDER BY bda.id DESC
        LIMIT 1
      `,
      [bookingNumber],
    );
    latestAssignmentStatus = assignmentRows[0]?.status ?? null;
    latestAssignmentReason = assignmentRows[0]?.assignment_reason ?? null;
  }

  return {
    booking_number: booking?.booking_number ?? bookingNumber,
    booking_status: booking?.booking_status ?? null,
    current_negotiation_id: booking?.current_negotiation_id ?? null,
    negotiation_id: negotiation?.id ?? targetNegotiationId,
    negotiation_status: negotiation?.negotiation_status ?? null,
    attempt_count: negotiation?.attempt_count ?? null,
    latest_attempt_outcome: latestAttemptOutcome,
    locked_driver_id: negotiation?.locked_driver_id ?? null,
    active_assignment_count: activeAssignmentCount,
    assignment_status: latestAssignmentStatus,
    assignment_reason: latestAssignmentReason,
  };
}

function assertSnapshot(snapshot, expected, label) {
  for (const [key, value] of Object.entries(expected)) {
    if (snapshot[key] !== value) {
      throw new Error(
        `${label}: expected ${key}=${JSON.stringify(value)}, got ${JSON.stringify(snapshot[key])}`,
      );
    }
  }
}

async function setupDriverOnline(baseUrl, driverToken) {
  await fetchJson(baseUrl, '/api/v1/driver/online', {
    method: 'POST',
    headers: { authorization: `Bearer ${driverToken}` },
  });
}

async function setupDriverOffline(baseUrl, driverToken) {
  await fetchJson(baseUrl, '/api/v1/driver/offline', {
    method: 'POST',
    headers: { authorization: `Bearer ${driverToken}` },
  });
}

async function runLockedTimeoutScenario(ctx) {
  const { baseUrl, adminToken, driverToken, urgentService, pool, payload } = ctx;
  const created = await createUrgentBooking(baseUrl, payload);
  const bookingNumber = created.bookingNumber;
  const record = { bookingNumber, payload };

  await verifyContactFlow(baseUrl, {
    bookingNumber,
    guestAccessToken: created.guestAccessToken,
    adminToken,
  });

  const lock = await lockUrgentCall(baseUrl, driverToken, bookingNumber);
  if (!lock.ok) throw new Error(`Lock failed: ${lock.body?.error_code}`);
  const lockData = responseData(lock.body);
  const negotiationId = lockData.negotiationId;
  const lockExpiresAt = lockData.lockExpiresAt;

  const first = await urgentService.processDriverEtaTimeout(
    negotiationId,
    { nowMs: expiredNowMs(lockExpiresAt) },
  );
  if (!first || first.status !== 'BROADCASTING') {
    throw new Error(`Scenario A first timeout expected BROADCASTING, got ${first?.status ?? 'null'}`);
  }

  let snapshot = await fetchDbSnapshot(pool, bookingNumber, negotiationId);
  assertSnapshot(snapshot, {
    booking_status: 'OPEN',
    negotiation_status: 'BROADCASTING',
    attempt_count: 1,
    latest_attempt_outcome: 'DRIVER_ETA_TIMEOUT',
    locked_driver_id: null,
    active_assignment_count: 0,
  }, 'Scenario A after first timeout');

  const second = await urgentService.processDriverEtaTimeout(
    negotiationId,
    { nowMs: expiredNowMs(lockExpiresAt) },
  );
  if (second != null) {
    throw new Error('Scenario A second timeout should no-op');
  }

  snapshot = await fetchDbSnapshot(pool, bookingNumber, negotiationId);
  assertSnapshot(snapshot, {
    booking_status: 'OPEN',
    negotiation_status: 'BROADCASTING',
    attempt_count: 1,
    latest_attempt_outcome: 'DRIVER_ETA_TIMEOUT',
  }, 'Scenario A after second timeout');

  await cleanupRegressionBooking(baseUrl, {
    adminToken,
    driverToken,
    record,
  });

  return {
    scenario: 'A_LOCKED_TIMEOUT',
    bookingNumber,
    negotiationId,
    firstTimeoutStatus: first.status,
    secondTimeoutNoOp: second == null,
    snapshot,
  };
}

async function runAwaitingCustomerTimeoutScenario(ctx) {
  const { baseUrl, adminToken, driverToken, urgentService, pool, payload } = ctx;
  const created = await createUrgentBooking(baseUrl, payload);
  const bookingNumber = created.bookingNumber;
  const record = { bookingNumber, payload };

  await verifyContactFlow(baseUrl, {
    bookingNumber,
    guestAccessToken: created.guestAccessToken,
    adminToken,
  });

  const lock = await lockUrgentCall(baseUrl, driverToken, bookingNumber);
  if (!lock.ok) throw new Error(`Lock failed: ${lock.body?.error_code}`);
  const negotiationId = responseData(lock.body).negotiationId;

  const eta = await submitUrgentEta(baseUrl, driverToken, bookingNumber, ETA_MINUTES);
  if (!eta.ok) throw new Error(`ETA submit failed: ${eta.body?.error_code}`);
  const etaData = responseData(eta.body);
  const customerDecisionExpiresAt = etaData.customerDecisionExpiresAt;

  const first = await urgentService.processCustomerDecisionTimeout(
    negotiationId,
    { nowMs: expiredNowMs(customerDecisionExpiresAt) },
  );
  if (!first || first.status !== 'BROADCASTING') {
    throw new Error(`Scenario B first timeout expected BROADCASTING, got ${first?.status ?? 'null'}`);
  }

  let snapshot = await fetchDbSnapshot(pool, bookingNumber, negotiationId);
  assertSnapshot(snapshot, {
    booking_status: 'OPEN',
    negotiation_status: 'BROADCASTING',
    attempt_count: 1,
    latest_attempt_outcome: 'CUSTOMER_AUTO_REJECTED',
    active_assignment_count: 0,
  }, 'Scenario B after first timeout');

  const second = await urgentService.processCustomerDecisionTimeout(
    negotiationId,
    { nowMs: expiredNowMs(customerDecisionExpiresAt) },
  );
  if (second != null) {
    throw new Error('Scenario B second timeout should no-op');
  }

  snapshot = await fetchDbSnapshot(pool, bookingNumber, negotiationId);
  assertSnapshot(snapshot, {
    negotiation_status: 'BROADCASTING',
    attempt_count: 1,
    latest_attempt_outcome: 'CUSTOMER_AUTO_REJECTED',
  }, 'Scenario B after second timeout');

  await cleanupRegressionBooking(baseUrl, {
    adminToken,
    driverToken,
    record,
  });

  return {
    scenario: 'B_AWAITING_CUSTOMER_TIMEOUT',
    bookingNumber,
    negotiationId,
    firstTimeoutStatus: first.status,
    secondTimeoutNoOp: second == null,
    snapshot,
  };
}

async function runAcceptGuardScenario(ctx) {
  const { baseUrl, adminToken, driverToken, urgentService, pool, payload } = ctx;
  const created = await createUrgentBooking(baseUrl, payload);
  const bookingNumber = created.bookingNumber;
  const record = { bookingNumber, payload };

  await verifyContactFlow(baseUrl, {
    bookingNumber,
    guestAccessToken: created.guestAccessToken,
    adminToken,
  });

  const lock = await lockUrgentCall(baseUrl, driverToken, bookingNumber);
  if (!lock.ok) throw new Error(`Lock failed: ${lock.body?.error_code}`);
  const negotiationId = responseData(lock.body).negotiationId;

  const eta = await submitUrgentEta(baseUrl, driverToken, bookingNumber, ETA_MINUTES);
  if (!eta.ok) throw new Error(`ETA submit failed: ${eta.body?.error_code}`);
  const customerDecisionExpiresAt = responseData(eta.body).customerDecisionExpiresAt;

  const accept = await submitUrgentDecision(
    baseUrl,
    bookingNumber,
    'ACCEPT',
    created.guestAccessToken,
  );
  if (!accept.ok) throw new Error(`Customer accept failed: ${accept.body?.error_code}`);

  let snapshot = await fetchDbSnapshot(pool, bookingNumber, negotiationId);
  assertSnapshot(snapshot, {
    booking_status: 'DRIVER_ASSIGNED',
    negotiation_status: 'CONFIRMED',
    active_assignment_count: 1,
    latest_attempt_outcome: 'CUSTOMER_ACCEPTED',
    assignment_reason: 'URGENT_CUSTOMER_CONFIRMED',
  }, 'Scenario C after accept');

  const timeoutAttempt = await urgentService.processCustomerDecisionTimeout(
    negotiationId,
    { nowMs: expiredNowMs(customerDecisionExpiresAt) },
  );
  if (timeoutAttempt != null) {
    throw new Error('Scenario C timeout must no-op after customer accept');
  }

  snapshot = await fetchDbSnapshot(pool, bookingNumber, negotiationId);
  assertSnapshot(snapshot, {
    booking_status: 'DRIVER_ASSIGNED',
    negotiation_status: 'CONFIRMED',
    active_assignment_count: 1,
    latest_attempt_outcome: 'CUSTOMER_ACCEPTED',
  }, 'Scenario C after timeout attempt');

  await cleanupRegressionBooking(baseUrl, {
    adminToken,
    driverToken,
    record,
  });

  return {
    scenario: 'C_ACCEPT_GUARD',
    bookingNumber,
    negotiationId,
    timeoutNoOp: timeoutAttempt == null,
    snapshot,
  };
}

async function runStalePointerScenario(ctx) {
  const { baseUrl, adminToken, driverToken, urgentService, pool, payload } = ctx;
  const created = await createUrgentBooking(baseUrl, payload);
  const bookingNumber = created.bookingNumber;
  const record = { bookingNumber, payload };

  await verifyContactFlow(baseUrl, {
    bookingNumber,
    guestAccessToken: created.guestAccessToken,
    adminToken,
  });

  const lock = await lockUrgentCall(baseUrl, driverToken, bookingNumber);
  if (!lock.ok) throw new Error(`Lock failed: ${lock.body?.error_code}`);
  const oldNegotiationId = responseData(lock.body).negotiationId;
  const lockExpiresAt = responseData(lock.body).lockExpiresAt;

  const eta = await submitUrgentEta(baseUrl, driverToken, bookingNumber, ETA_MINUTES);
  if (!eta.ok) throw new Error(`ETA submit failed: ${eta.body?.error_code}`);

  const accept = await submitUrgentDecision(
    baseUrl,
    bookingNumber,
    'ACCEPT',
    created.guestAccessToken,
  );
  if (!accept.ok) throw new Error(`Customer accept failed: ${accept.body?.error_code}`);

  const unassign = await adminUnassign(baseUrl, adminToken, bookingNumber);
  if (!unassign.ok) throw new Error(`Admin unassign failed: ${unassign.body?.error_code}`);

  const currentNegotiation = await fetchUrgentNegotiation(
    baseUrl,
    bookingNumber,
    created.guestAccessToken,
  );
  const newNegotiationId = currentNegotiation.negotiationId;
  if (Number(newNegotiationId) === Number(oldNegotiationId)) {
    throw new Error('Scenario D expected a new negotiation id after admin unassign');
  }

  let currentSnapshot = await fetchDbSnapshot(pool, bookingNumber, newNegotiationId);
  assertSnapshot(currentSnapshot, {
    booking_status: 'OPEN',
    negotiation_status: 'BROADCASTING',
    current_negotiation_id: newNegotiationId,
  }, 'Scenario D current negotiation after unassign');

  const staleTimeout = await urgentService.processDriverEtaTimeout(
    oldNegotiationId,
    { nowMs: expiredNowMs(lockExpiresAt) },
  );
  if (staleTimeout != null) {
    throw new Error('Scenario D stale negotiation timeout must no-op');
  }

  currentSnapshot = await fetchDbSnapshot(pool, bookingNumber, newNegotiationId);
  assertSnapshot(currentSnapshot, {
    booking_status: 'OPEN',
    negotiation_status: 'BROADCASTING',
    current_negotiation_id: newNegotiationId,
  }, 'Scenario D current negotiation after stale timeout');

  const oldSnapshot = await fetchDbSnapshot(pool, bookingNumber, oldNegotiationId);
  assertSnapshot(oldSnapshot, {
    negotiation_status: 'CONFIRMED',
  }, 'Scenario D old negotiation unchanged');

  await cleanupRegressionBooking(baseUrl, {
    adminToken,
    driverToken,
    record,
  });

  return {
    scenario: 'D_STALE_POINTER',
    bookingNumber,
    oldNegotiationId,
    newNegotiationId,
    staleTimeoutNoOp: staleTimeout == null,
    currentSnapshot,
    oldSnapshot,
  };
}

async function main() {
  loadE2eLocalEnv();
  const { baseUrl } = assertSafeEnvironment({ dryRun: false });
  const payload = bookingPayload();
  const { error } = createBookingSchema.validate(payload, { abortEarly: false });
  if (error) throw new Error(`Invalid payload: ${error.message}`);

  const report = {
    WORKER_CONFIG: workerConfigReport(),
    DIRECT_DB_MUTATION_USED: 'NO',
    CLEANUP_API_BASED: 'YES',
    SCENARIOS: {},
  };

  let adminToken;
  let driverToken;
  let driverWasOnline = false;

  try {
    const adminLogin = await login(baseUrl, process.env.TRIDE_ADMIN_EMAIL, process.env.TRIDE_ADMIN_PASSWORD);
    const driverLogin = await login(baseUrl, process.env.TRIDE_TEST_DRIVER_EMAIL, process.env.TRIDE_TEST_DRIVER_PASSWORD);
    adminToken = adminLogin.token;
    driverToken = driverLogin.token;

    await assertTestDriverEligibleForNewJob(baseUrl, adminToken);
    await setupDriverOnline(baseUrl, driverToken);
    driverWasOnline = true;

    const urgentService = await getUrgentNegotiationService();
    const pool = await getDbPool();

    const ctx = { baseUrl, adminToken, driverToken, urgentService, pool, payload };

    report.SCENARIOS.A = await runLockedTimeoutScenario(ctx);
    report.SCENARIOS.B = await runAwaitingCustomerTimeoutScenario(ctx);
    report.SCENARIOS.C = await runAcceptGuardScenario(ctx);
    report.SCENARIOS.D = await runStalePointerScenario(ctx);

    console.log('URGENT_TIMEOUT_HARDENING_E2E_RESULT_JSON');
    console.log(JSON.stringify(report, null, 2));
  } catch (err) {
    console.error(formatCleanupFailure('unknown', err.message));
    throw err;
  } finally {
    if (driverWasOnline && driverToken) {
      try {
        await setupDriverOffline(baseUrl, driverToken);
      } catch (offlineErr) {
        console.error(`Driver offline cleanup failed: ${offlineErr.message}`);
      }
    }
  }
}

if (require.main === module) {
  main().catch((err) => {
    console.error('URGENT_TIMEOUT_HARDENING_E2E_FAIL');
    console.error(err.message);
    process.exit(1);
  });
}

module.exports = {
  main,
  bookingPayload,
  expiredNowMs,
  loadE2eLocalEnv,
  workerConfigReport,
  fetchDbSnapshot,
  REGRESSION_MARKER,
  CUSTOMER_NAME,
  ETA_MINUTES,
};
