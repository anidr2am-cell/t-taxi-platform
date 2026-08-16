#!/usr/bin/env node
/**
 * Staging LIVE E2E: contact verified dispatch durable notification idempotency.
 * Creates [E2E] booking, verifies contact once, retries admin verify, asserts stable counts.
 * Cleanup via admin archive API only. DB checks are read-only (companion SQL file).
 */
const fs = require('node:fs');
const path = require('node:path');
const NOTIFICATION_TYPES = require('../src/constants/notificationTypes');
const { createBookingSchema } = require('../src/validators/booking.validator');
const {
  assertSafeEnvironment,
  assertValidBookingPayload,
  bookingPayload: regressionBookingPayload,
  toPricingPayload,
  createBookingIdempotencyKey,
  TEST_NAME_PREFIX,
  REGRESSION_MARKER,
} = require('./staging-booking-regression');
const {
  assertTestDriverEligibleForNewJob,
  cleanupRegressionBookings,
  formatCleanupFailure,
} = require('./e2eRegressionCleanup');

const E2E_MARKER = 'CONTACT_DISPATCH_DURABLE_E2E';
const CUSTOMER_NAME = '[E2E] Contact Dispatch Durable';
const TIMEOUT_MS = Number(process.env.TRIDE_REGRESSION_TIMEOUT_MS || 25000);
const PREFERRED_CHANNELS = ['LINE', 'WHATSAPP', 'KAKAO'];
const DRIVER_CALL_OPEN_KEY_PREFIX = 'driver-call-open';

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
}

function bookingPayload() {
  const payload = regressionBookingPayload({
    customerName: CUSTOMER_NAME,
    flightNumber: 'TG402',
  });
  return {
    ...payload,
    customer: {
      ...payload.customer,
      phone: '+66000000004',
      email: 'contact-dispatch-durable-e2e@example.com',
    },
    options: {
      nameSign: true,
      nameSignText: 'E2E Contact Dispatch Durable',
    },
  };
}

function buildCreateBookingRequest(payload) {
  return payload;
}

function buildContactDispatchIdempotencyKey(bookingId, driverId) {
  return `${DRIVER_CALL_OPEN_KEY_PREFIX}:${bookingId}:${driverId}`;
}

function buildContactDispatchIdempotencyKeyPattern() {
  return `${DRIVER_CALL_OPEN_KEY_PREFIX}:<bookingId>:<driverId>`;
}

function formatValidationErrors(errors) {
  return errors
    .map((item) => [item.field, item.type, item.source].filter(Boolean).join(':'))
    .filter(Boolean)
    .join(', ');
}

function formatCreateBookingFailure(create) {
  const message = create.body?.error_code || create.body?.message || 'UNKNOWN';
  const details = Array.isArray(create.body?.errors)
    ? formatValidationErrors(create.body.errors)
    : '';
  const suffix = details ? ` (${details})` : '';
  return `Create booking failed: HTTP ${create.status} ${message}${suffix}`;
}

function responseData(body) {
  return body?.data ?? body;
}

function countTargetDriverCallNotifications(items, bookingNumber) {
  return items.filter((row) => row.payload?.bookingNumber === bookingNumber
    && row.notificationType === NOTIFICATION_TYPES.DRIVER_CALL_AVAILABLE).length;
}

function printSafeDiagnostics(report) {
  console.log(`BOOKING=${report.BOOKING ?? ''}`);
  console.log(`TEST_DRIVER_ID=${report.TEST_DRIVER_ID ?? ''}`);
  console.log(`TEST_DRIVER_ELIGIBLE=${report.TEST_DRIVER_ELIGIBLE ?? ''}`);
  console.log(`FIRST_VERIFY_STATUS=${report.FIRST_VERIFY_STATUS ?? ''}`);
  console.log(`FIRST_VERIFY_DISPATCH_STARTED=${report.FIRST_VERIFY_DISPATCH_STARTED ?? ''}`);
  console.log(`OPEN_CALL_VISIBLE_AFTER_FIRST_VERIFY=${report.OPEN_CALL_VISIBLE_AFTER_FIRST_VERIFY ?? ''}`);
  console.log(`EXPECTED_IDEMPOTENCY_KEY_PATTERN=${report.EXPECTED_IDEMPOTENCY_KEY_PATTERN ?? ''}`);
  console.log(`FIRST_TARGET_DRIVER_NOTIFICATION_COUNT=${report.FIRST_TARGET_DRIVER_NOTIFICATION_COUNT ?? ''}`);
  console.log(`RETRY_TARGET_DRIVER_NOTIFICATION_COUNT=${report.RETRY_TARGET_DRIVER_NOTIFICATION_COUNT ?? ''}`);
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
  return { token, user: body?.data?.user ?? body?.data ?? null };
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

async function verifyContact(baseUrl, { bookingNumber, guestAccessToken, adminToken }) {
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
  return fetchJson(
    baseUrl,
    `/api/v1/admin/bookings/${bookingNumber}/contact/verify`,
    {
      method: 'POST',
      headers: { authorization: `Bearer ${adminToken}` },
    },
  );
}

async function listDriverCallNotifications(baseUrl, driverToken) {
  const list = responseData((await fetchJson(
    baseUrl,
    `/api/v1/driver/notifications?limit=100&notificationType=${NOTIFICATION_TYPES.DRIVER_CALL_AVAILABLE}`,
    { headers: { authorization: `Bearer ${driverToken}` } },
  )).body);
  return Array.isArray(list?.items) ? list.items : [];
}

async function isOpenCallVisible(baseUrl, driverToken, bookingNumber) {
  const openCalls = responseData((await fetchJson(baseUrl, '/api/v1/driver/calls/open', {
    headers: { authorization: `Bearer ${driverToken}` },
  })).body);
  return (openCalls?.items ?? []).some((row) => row.bookingNumber === bookingNumber);
}

async function runApiCleanup(baseUrl, {
  adminToken,
  driverToken,
  bookingNumber,
  requestPayload,
}) {
  await cleanupRegressionBookings(baseUrl, {
    adminToken,
    driverToken,
    records: [{ bookingNumber, payload: requestPayload }],
  });
  console.log('CLEANUP_API_BASED=YES');
  console.log('CLEANUP_RESULT=PASS');
}

async function main() {
  loadE2eLocalEnv();
  const { baseUrl } = assertSafeEnvironment({ dryRun: false });
  const payload = bookingPayload();
  const requestPayload = buildCreateBookingRequest(payload);
  assertValidBookingPayload(requestPayload, 'contact dispatch durable request');

  const report = {
    BOOKING: null,
    TEST_DRIVER_ID: null,
    TEST_DRIVER_ELIGIBLE: null,
    FIRST_VERIFY_STATUS: null,
    FIRST_VERIFY_DISPATCH_STARTED: null,
    OPEN_CALL_VISIBLE_AFTER_FIRST_VERIFY: null,
    EXPECTED_IDEMPOTENCY_KEY_PATTERN: buildContactDispatchIdempotencyKeyPattern(),
    FIRST_TARGET_DRIVER_NOTIFICATION_COUNT: null,
    RETRY_TARGET_DRIVER_NOTIFICATION_COUNT: null,
    OPEN_CALL_VISIBLE: null,
  };

  let adminToken;
  let driverToken;
  let driverWasOnline = false;
  let bookingNumber = null;

  try {
    const adminLogin = await login(baseUrl, process.env.TRIDE_ADMIN_EMAIL, process.env.TRIDE_ADMIN_PASSWORD);
    const driverLogin = await login(
      baseUrl,
      process.env.TRIDE_TEST_DRIVER_EMAIL,
      process.env.TRIDE_TEST_DRIVER_PASSWORD,
    );
    adminToken = adminLogin.token;
    driverToken = driverLogin.token;

    const testDriver = await assertTestDriverEligibleForNewJob(
      baseUrl,
      adminToken,
      driverLogin.user?.name ?? `${TEST_NAME_PREFIX} Regression Driver`,
    );
    report.TEST_DRIVER_ID = testDriver.id;
    report.TEST_DRIVER_ELIGIBLE = testDriver.assignmentEligible === true;

    await fetchJson(baseUrl, '/api/v1/driver/online', {
      method: 'POST',
      headers: { authorization: `Bearer ${driverToken}` },
    });
    driverWasOnline = true;

    await fetchJson(baseUrl, '/api/v1/bookings/pricing/calculate', {
      method: 'POST',
      body: JSON.stringify(toPricingPayload(requestPayload)),
    });

    const create = await fetchJson(baseUrl, '/api/v1/bookings', {
      method: 'POST',
      headers: {
        'Idempotency-Key': createBookingIdempotencyKey(),
      },
      body: JSON.stringify(requestPayload),
    });
    if (!create.ok) throw new Error(formatCreateBookingFailure(create));
    bookingNumber = responseData(create.body)?.bookingNumber;
    const guestAccessToken = responseData(create.body)?.guestAccessToken;
    if (!bookingNumber || !guestAccessToken) throw new Error('Create booking missing identifiers');
    report.BOOKING = bookingNumber;

    const firstVerify = await verifyContact(baseUrl, { bookingNumber, guestAccessToken, adminToken });
    report.FIRST_VERIFY_STATUS = firstVerify.status;
    if (!firstVerify.ok) throw new Error(`First admin verify failed: ${firstVerify.body?.error_code}`);
    report.FIRST_VERIFY_DISPATCH_STARTED = responseData(firstVerify.body)?.dispatchStarted;
    report.OPEN_CALL_VISIBLE_AFTER_FIRST_VERIFY = await isOpenCallVisible(
      baseUrl,
      driverToken,
      bookingNumber,
    );
    printSafeDiagnostics(report);

    if (report.FIRST_VERIFY_DISPATCH_STARTED !== true) {
      throw new Error(
        `Contact dispatch did not start (dispatchStarted=${report.FIRST_VERIFY_DISPATCH_STARTED})`,
      );
    }
    if (!report.OPEN_CALL_VISIBLE_AFTER_FIRST_VERIFY) {
      throw new Error(
        'E2E driver cannot see open call after verify; driver may be ineligible (online/vehicle/settlement)',
      );
    }

    const firstNotifications = await listDriverCallNotifications(baseUrl, driverToken);
    report.FIRST_TARGET_DRIVER_NOTIFICATION_COUNT = countTargetDriverCallNotifications(
      firstNotifications,
      bookingNumber,
    );
    if (report.FIRST_TARGET_DRIVER_NOTIFICATION_COUNT !== 1) {
      throw new Error(
        `Expected exactly one DRIVER_CALL_AVAILABLE notification for E2E driver ${report.TEST_DRIVER_ID}, got ${report.FIRST_TARGET_DRIVER_NOTIFICATION_COUNT}`,
      );
    }

    const retryVerify = await verifyContact(baseUrl, { bookingNumber, guestAccessToken, adminToken });
    if (!retryVerify.ok) throw new Error(`Retry admin verify failed: ${retryVerify.body?.error_code}`);
    report.RETRY_VERIFY_DISPATCH_STARTED = responseData(retryVerify.body)?.dispatchStarted;

    const retryNotifications = await listDriverCallNotifications(baseUrl, driverToken);
    report.RETRY_TARGET_DRIVER_NOTIFICATION_COUNT = countTargetDriverCallNotifications(
      retryNotifications,
      bookingNumber,
    );
    if (report.RETRY_TARGET_DRIVER_NOTIFICATION_COUNT !== report.FIRST_TARGET_DRIVER_NOTIFICATION_COUNT) {
      throw new Error('Retry verify changed durable notification count for E2E driver');
    }

    report.OPEN_CALL_VISIBLE = await isOpenCallVisible(baseUrl, driverToken, bookingNumber);
    if (!report.OPEN_CALL_VISIBLE) {
      throw new Error('Booking not visible in open calls after contact dispatch retry');
    }

    printSafeDiagnostics(report);
    console.log(`CONTACT_DISPATCH_E2E_BOOKING=${bookingNumber}`);
    console.log(JSON.stringify({ ok: true, report }, null, 2));
  } catch (err) {
    console.error(JSON.stringify({ ok: false, error: err.message }, null, 2));
    process.exitCode = 1;
    if (bookingNumber) {
      printSafeDiagnostics(report);
    }
    throw err;
  } finally {
    if (bookingNumber && adminToken && driverToken) {
      try {
        await runApiCleanup(baseUrl, {
          adminToken,
          driverToken,
          bookingNumber,
          requestPayload,
        });
      } catch (cleanupErr) {
        console.error(formatCleanupFailure(bookingNumber, cleanupErr.message));
        process.exitCode = 1;
      }
    }
    if (driverWasOnline && driverToken) {
      try {
        await fetchJson(baseUrl, '/api/v1/driver/offline', {
          method: 'POST',
          headers: { authorization: `Bearer ${driverToken}` },
        });
      } catch (offlineErr) {
        console.error(`Driver offline cleanup failed: ${offlineErr.message}`);
        process.exitCode = 1;
      }
    }
  }
}

if (require.main === module) {
  main().catch(() => {
    // exitCode already set in main
  });
}

module.exports = {
  E2E_MARKER,
  CUSTOMER_NAME,
  DRIVER_CALL_OPEN_KEY_PREFIX,
  bookingPayload,
  buildCreateBookingRequest,
  buildContactDispatchIdempotencyKey,
  buildContactDispatchIdempotencyKeyPattern,
  countTargetDriverCallNotifications,
  formatCreateBookingFailure,
  printSafeDiagnostics,
  runApiCleanup,
};
