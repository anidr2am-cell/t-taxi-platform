#!/usr/bin/env node
/**
 * Staging LIVE E2E: contact verified dispatch durable notification idempotency.
 * Creates [E2E] booking, verifies contact once, retries admin verify, asserts stable counts.
 * Cleanup via admin archive API only. DB checks are read-only (companion SQL file).
 */
const fs = require('node:fs');
const path = require('node:path');
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
  cleanupRegressionBookings,
  formatCleanupFailure,
} = require('./e2eRegressionCleanup');

const E2E_MARKER = 'CONTACT_DISPATCH_DURABLE_E2E';
const CUSTOMER_NAME = '[E2E] Contact Dispatch Durable';
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
  return token;
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

async function countDriverCallNotifications(baseUrl, driverToken, bookingNumber) {
  const list = responseData((await fetchJson(baseUrl, '/api/v1/driver/notifications?limit=100', {
    headers: { authorization: `Bearer ${driverToken}` },
  })).body);
  const items = Array.isArray(list?.items) ? list.items : [];
  return items.filter((row) => row.payload?.bookingNumber === bookingNumber
    && row.type === 'DRIVER_CALL_AVAILABLE').length;
}

async function isOpenCallVisible(baseUrl, driverToken, bookingNumber) {
  const openCalls = responseData((await fetchJson(baseUrl, '/api/v1/driver/calls/open', {
    headers: { authorization: `Bearer ${driverToken}` },
  })).body);
  return (openCalls?.items ?? []).some((row) => row.bookingNumber === bookingNumber);
}

async function main() {
  loadE2eLocalEnv();
  const { baseUrl } = assertSafeEnvironment({ dryRun: false });
  const payload = bookingPayload();
  const requestPayload = buildCreateBookingRequest(payload);
  assertValidBookingPayload(requestPayload, 'contact dispatch durable request');

  const report = {
    BOOKING: null,
    FIRST_VERIFY_DISPATCH_STARTED: null,
    FIRST_NOTIFICATION_COUNT: null,
    RETRY_VERIFY_DISPATCH_STARTED: null,
    RETRY_NOTIFICATION_COUNT: null,
    OPEN_CALL_VISIBLE: null,
  };

  let adminToken;
  let driverToken;

  try {
    adminToken = await login(baseUrl, process.env.TRIDE_ADMIN_EMAIL, process.env.TRIDE_ADMIN_PASSWORD);
    driverToken = await login(
      baseUrl,
      process.env.TRIDE_TEST_DRIVER_EMAIL,
      process.env.TRIDE_TEST_DRIVER_PASSWORD,
    );

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
    const bookingNumber = responseData(create.body)?.bookingNumber;
    const guestAccessToken = responseData(create.body)?.guestAccessToken;
    if (!bookingNumber || !guestAccessToken) throw new Error('Create booking missing identifiers');
    report.BOOKING = bookingNumber;

    const firstVerify = await verifyContact(baseUrl, { bookingNumber, guestAccessToken, adminToken });
    if (!firstVerify.ok) throw new Error(`First admin verify failed: ${firstVerify.body?.error_code}`);
    report.FIRST_VERIFY_DISPATCH_STARTED = responseData(firstVerify.body)?.dispatchStarted;
    report.FIRST_NOTIFICATION_COUNT = await countDriverCallNotifications(baseUrl, driverToken, bookingNumber);
    if (report.FIRST_NOTIFICATION_COUNT < 1) {
      throw new Error('Expected at least one durable DRIVER_CALL_AVAILABLE notification after verify');
    }

    const retryVerify = await verifyContact(baseUrl, { bookingNumber, guestAccessToken, adminToken });
    if (!retryVerify.ok) throw new Error(`Retry admin verify failed: ${retryVerify.body?.error_code}`);
    report.RETRY_VERIFY_DISPATCH_STARTED = responseData(retryVerify.body)?.dispatchStarted;
    report.RETRY_NOTIFICATION_COUNT = await countDriverCallNotifications(baseUrl, driverToken, bookingNumber);
    if (report.RETRY_NOTIFICATION_COUNT !== report.FIRST_NOTIFICATION_COUNT) {
      throw new Error('Retry verify changed durable notification count');
    }

    report.OPEN_CALL_VISIBLE = await isOpenCallVisible(baseUrl, driverToken, bookingNumber);
    if (!report.OPEN_CALL_VISIBLE) {
      throw new Error('Booking not visible in open calls after contact dispatch');
    }

    console.log(`CONTACT_DISPATCH_E2E_BOOKING=${bookingNumber}`);
    console.log(JSON.stringify({ ok: true, report }, null, 2));
  } finally {
    if (report.BOOKING && adminToken && driverToken) {
      const cleanup = await cleanupRegressionBookings(baseUrl, {
        adminToken,
        driverToken,
        records: [{ bookingNumber: report.BOOKING, payload: requestPayload }],
      });
      if (!cleanup.ok) {
        console.error(formatCleanupFailure(cleanup));
        process.exitCode = 1;
      }
    }
  }
}

if (require.main === module) {
  main().catch((err) => {
    console.error(JSON.stringify({ ok: false, error: err.message }, null, 2));
    process.exitCode = 1;
  });
}

module.exports = {
  E2E_MARKER,
  CUSTOMER_NAME,
  bookingPayload,
  buildCreateBookingRequest,
  formatCreateBookingFailure,
};
