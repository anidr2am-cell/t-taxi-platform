#!/usr/bin/env node
/**
 * Staging LIVE E2E: settlement receipt upload idempotency (Phase 3 Step 2).
 * Creates [E2E] booking, drives to SETTLEMENT_PENDING, exercises receipt keys.
 */
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { createBookingSchema } = require('../src/validators/booking.validator');
const {
  assertSafeEnvironment,
  toPricingPayload,
  createBookingIdempotencyKey,
} = require('./staging-booking-regression');

const E2E_MARKER = 'RECEIPT_IDEMPOTENCY_E2E';
const CUSTOMER_NAME = '[E2E] Settlement Receipt Idempotency';
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

function futurePickup(offsetDays = 12) {
  const date = new Date();
  date.setUTCDate(date.getUTCDate() + offsetDays);
  date.setUTCHours(5, 15, 0, 0);
  return date.toISOString();
}

function bookingPayload() {
  return {
    serviceTypeCode: 'AIRPORT_PICKUP',
    vehicleTypeCode: 'SUV',
    vehicleCount: 1,
    scheduledPickupAt: futurePickup(),
    origin: {
      name: 'Suvarnabhumi Airport',
      address: 'Suvarnabhumi Airport, Bangkok, Thailand',
      placeId: 'staging-bkk',
    },
    destination: {
      name: 'Pattaya',
      address: 'Pattaya, Chon Buri, Thailand',
      placeId: 'staging-pattaya',
    },
    originAirportIata: 'BKK',
    destinationLocationCode: 'PATTAYA',
    transfer: { airportIata: 'BKK', flightNumber: 'TG403' },
    passengers: { adults: 2, children: 0, infants: 0 },
    luggage: { carriers20Inch: 1, carriers24InchPlus: 0, golfBags: 0 },
    options: { nameSign: true, nameSignText: 'E2E Receipt Idempotency' },
    customer: {
      name: CUSTOMER_NAME,
      phone: '+66000000004',
      email: 'receipt-idempotency-e2e@example.com',
      countryCode: 'TH',
    },
    additionalRequests: E2E_MARKER,
  };
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
  return { token, user: body?.data?.user ?? body?.data ?? null };
}

async function uploadReceipt(baseUrl, driverToken, bookingNumber, pdfBytes, idempotencyKey) {
  const form = new FormData();
  form.append('file', new Blob([pdfBytes], { type: 'application/pdf' }), 'receipt.pdf');
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);
  try {
    const response = await fetch(`${baseUrl}/api/v1/driver/settlements/${bookingNumber}/receipt`, {
      method: 'POST',
      headers: {
        authorization: `Bearer ${driverToken}`,
        'Idempotency-Key': idempotencyKey,
      },
      body: form,
      signal: controller.signal,
    });
    const text = await response.text();
    const body = text ? JSON.parse(text) : null;
    return { ok: response.ok, status: response.status, body };
  } finally {
    clearTimeout(timer);
  }
}

function pdfBytes(label) {
  return Buffer.from(`%PDF-1.4\n${label}-${crypto.randomUUID()}\n`, 'utf8');
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

async function verifyContactFlow(baseUrl, { bookingNumber, guestAccessToken, adminToken, driverToken }) {
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
  const openCalls = responseData((await fetchJson(baseUrl, '/api/v1/driver/calls/open', {
    headers: { authorization: `Bearer ${driverToken}` },
  })).body);
  const visible = (openCalls?.items ?? []).some((row) => row.bookingNumber === bookingNumber);
  if (!visible) throw new Error('Booking not visible in open calls after VERIFIED');
}

async function claimOpenCall(baseUrl, driverToken, bookingNumber, driverVehicleId) {
  return fetchJson(baseUrl, `/api/v1/driver/calls/${bookingNumber}/claim`, {
    method: 'POST',
    headers: { authorization: `Bearer ${driverToken}` },
    body: JSON.stringify({ driverVehicleId }),
  });
}

async function archiveBooking(baseUrl, adminToken, bookingNumber) {
  return fetchJson(baseUrl, '/api/v1/admin/bookings/archive', {
    method: 'POST',
    headers: { authorization: `Bearer ${adminToken}` },
    body: JSON.stringify({ bookingNumbers: [bookingNumber], reason: E2E_MARKER }),
  });
}

async function driveToSettlementPending(baseUrl, {
  adminToken,
  driverToken,
  bookingNumber,
  guestAccessToken,
}) {
  await verifyContactFlow(baseUrl, {
    bookingNumber,
    guestAccessToken,
    adminToken,
    driverToken,
  });

  const openCalls = responseData((await fetchJson(baseUrl, '/api/v1/driver/calls/open', {
    headers: { authorization: `Bearer ${driverToken}` },
  })).body);
  const openItem = (openCalls?.items ?? []).find((row) => row.bookingNumber === bookingNumber);
  if (!openItem?.compatibleVehicles?.length) {
    throw new Error('No compatible vehicle for claim');
  }
  const claim = await claimOpenCall(
    baseUrl,
    driverToken,
    bookingNumber,
    openItem.compatibleVehicles[0].id,
  );
  if (!claim.ok) throw new Error(`Claim failed: ${claim.body?.error_code}`);

  for (const action of ['start-route', 'arrive', 'mark-picked-up', 'end-trip']) {
    const step = await fetchJson(baseUrl, `/api/v1/driver/bookings/${bookingNumber}/${action}`, {
      method: 'POST',
      headers: { authorization: `Bearer ${driverToken}` },
    });
    if (!step.ok) throw new Error(`${action} failed: ${step.body?.error_code}`);
  }
}

async function main() {
  loadE2eLocalEnv();
  const { baseUrl } = assertSafeEnvironment({ dryRun: false });
  const payload = bookingPayload();
  const { error } = createBookingSchema.validate(payload, { abortEarly: false });
  if (error) throw new Error(`Invalid payload: ${error.message}`);

  const report = {
    BOOKING: null,
    FIRST_STATUS: null,
    FIRST_RECEIPT_FILE_ID: null,
    FIRST_IDEMPOTENT: null,
    RETRY_STATUS: null,
    RETRY_RECEIPT_FILE_ID: null,
    RETRY_IDEMPOTENT: null,
    CONFLICT_STATUS: null,
    CONFLICT_ERROR: null,
  };

  let adminToken;
  let driverToken;
  let driverWasOnline = false;
  let bookingNumber = null;
  const receiptKey = createBookingIdempotencyKey();

  try {
    const adminLogin = await login(baseUrl, process.env.TRIDE_ADMIN_EMAIL, process.env.TRIDE_ADMIN_PASSWORD);
    const driverLogin = await login(baseUrl, process.env.TRIDE_TEST_DRIVER_EMAIL, process.env.TRIDE_TEST_DRIVER_PASSWORD);
    adminToken = adminLogin.token;
    driverToken = driverLogin.token;

    await fetchJson(baseUrl, '/api/v1/driver/online', {
      method: 'POST',
      headers: { authorization: `Bearer ${driverToken}` },
    });
    driverWasOnline = true;

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
    bookingNumber = createdData.bookingNumber;
    report.BOOKING = bookingNumber;

    await driveToSettlementPending(baseUrl, {
      adminToken,
      driverToken,
      bookingNumber,
      guestAccessToken: createdData.guestAccessToken,
    });

    const firstBytes = pdfBytes('first');
    const first = await uploadReceipt(baseUrl, driverToken, bookingNumber, firstBytes, receiptKey);
    report.FIRST_STATUS = first.status;
    const firstData = responseData(first.body);
    report.FIRST_RECEIPT_FILE_ID = firstData?.receiptFileId ?? null;
    report.FIRST_IDEMPOTENT = firstData?.idempotent ?? null;
    if (!first.ok) throw new Error(`First upload failed: ${first.body?.error_code}`);

    const retry = await uploadReceipt(baseUrl, driverToken, bookingNumber, firstBytes, receiptKey);
    report.RETRY_STATUS = retry.status;
    const retryData = responseData(retry.body);
    report.RETRY_RECEIPT_FILE_ID = retryData?.receiptFileId ?? null;
    report.RETRY_IDEMPOTENT = retryData?.idempotent ?? null;
    if (!retry.ok) throw new Error(`Same-key retry failed: ${retry.body?.error_code}`);
    if (report.RETRY_RECEIPT_FILE_ID !== report.FIRST_RECEIPT_FILE_ID) {
      throw new Error('Retry returned different receiptFileId');
    }
    if (report.RETRY_IDEMPOTENT !== true) {
      throw new Error('Retry did not set idempotent=true');
    }

    const conflict = await uploadReceipt(
      baseUrl,
      driverToken,
      bookingNumber,
      pdfBytes('different'),
      receiptKey,
    );
    report.CONFLICT_STATUS = conflict.status;
    report.CONFLICT_ERROR = conflict.body?.error_code ?? null;
    if (conflict.status !== 409 || report.CONFLICT_ERROR !== 'IDEMPOTENCY_KEY_REUSED') {
      throw new Error(`Expected 409 IDEMPOTENCY_KEY_REUSED, got ${conflict.status} ${report.CONFLICT_ERROR}`);
    }

    await archiveBooking(baseUrl, adminToken, bookingNumber);
    console.log(JSON.stringify(report, null, 2));
    console.log('PASS receipt idempotency E2E');
  } catch (err) {
    console.error(`FAIL receipt idempotency E2E: ${err.message}`);
    console.log(JSON.stringify(report, null, 2));
    process.exitCode = 1;
    if (bookingNumber && adminToken) {
      try {
        await archiveBooking(baseUrl, adminToken, bookingNumber);
      } catch (cleanupErr) {
        console.error(`Cleanup archive failed: ${cleanupErr.message}`);
      }
    }
  } finally {
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
  main().catch((err) => {
    console.error(err.message);
    process.exit(1);
  });
}

module.exports = { main };
