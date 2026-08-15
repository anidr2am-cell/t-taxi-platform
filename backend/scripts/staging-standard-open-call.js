#!/usr/bin/env node
/**
 * Staging E2E: STANDARD booking contact gate -> driver open-call visibility.
 *
 * Safe by design:
 * - Only runs against https://trider.taxi
 * - Requires [E2E] test accounts
 * - Archives only bookings it created with the E2E marker
 * - Never logs passwords or tokens
 */
const { createBookingSchema } = require('../src/validators/booking.validator');
const { loginSchema } = require('../src/validators/auth.validator');
const {
  assertSafeEnvironment,
  TEST_NAME_PREFIX,
  toPricingPayload,
} = require('./staging-booking-regression');

const E2E_MARKER = 'AUTOMATED_STANDARD_OPEN_CALL_E2E';
const CUSTOMER_NAME = '[E2E] STANDARD Open Call';
const TIMEOUT_MS = Number(process.env.TRIDE_REGRESSION_TIMEOUT_MS || 15000);
const OPEN_CALL_POLL_TIMEOUT_MS = Number(process.env.TRIDE_OPEN_CALL_POLL_TIMEOUT_MS || 10000);
const OPEN_CALL_POLL_INTERVAL_MS = Number(process.env.TRIDE_OPEN_CALL_POLL_INTERVAL_MS || 500);
const PREFERRED_CHANNELS = ['LINE', 'WHATSAPP', 'KAKAO'];

function hasArg(name) {
  return process.argv.slice(2).includes(name);
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function normalizeEmail(value) {
  return String(value ?? '').trim().toLowerCase();
}

function isValidEmail(value) {
  const { error } = loginSchema.validate({ email: normalizeEmail(value), password: 'validation-only' });
  return !error;
}

function futurePickup(offsetDays = 7) {
  const date = new Date();
  date.setUTCDate(date.getUTCDate() + offsetDays);
  date.setUTCHours(3, 30, 0, 0);
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
    transfer: { airportIata: 'BKK', flightNumber: 'TG401' },
    passengers: { adults: 2, children: 0, infants: 0 },
    luggage: { carriers20Inch: 1, carriers24InchPlus: 1, golfBags: 0 },
    options: { nameSign: true, nameSignText: 'E2E Standard Open Call' },
    customer: {
      name: CUSTOMER_NAME,
      phone: '+66000000002',
      email: 'standard-open-call-e2e@example.com',
      countryCode: 'TH',
    },
    additionalRequests: E2E_MARKER,
  };
}

function assertValidPayload(payload) {
  const { error } = createBookingSchema.validate(payload, {
    abortEarly: false,
    stripUnknown: false,
  });
  if (error) {
    const details = error.details.map((detail) => detail.path.join('.')).join(', ');
    throw new Error(`Booking payload is invalid (${details})`);
  }
}

function responseData(body) {
  return body?.data ?? body;
}

function formatHttpError(path, status, body, message) {
  const details = Array.isArray(body?.errors)
    ? body.errors
      .map((item) => [item.field, item.type, item.source].filter(Boolean).join(':'))
      .filter(Boolean)
      .join(', ')
    : '';
  const suffix = details ? ` (${details})` : '';
  return `${path} failed: HTTP ${status} ${message}${suffix}`;
}

async function fetchJson(baseUrl, path, options = {}) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);
  try {
    const response = await fetch(`${baseUrl}${path}`, {
      ...options,
      headers: {
        'content-type': 'application/json',
        ...(options.headers || {}),
      },
      signal: controller.signal,
    });
    const text = await response.text();
    const body = text ? JSON.parse(text) : null;
    if (!response.ok) {
      const message = body?.error_code || body?.message || `HTTP ${response.status}`;
      throw new Error(formatHttpError(path, response.status, body, message));
    }
    return body;
  } finally {
    clearTimeout(timer);
  }
}

async function login(baseUrl, email, password) {
  if (!isValidEmail(email)) {
    throw new Error('Login email must be a valid email address.');
  }
  const body = await fetchJson(baseUrl, '/api/v1/auth/login', {
    method: 'POST',
    body: JSON.stringify({ email: normalizeEmail(email), password }),
  });
  const token = body?.data?.accessToken || body?.data?.access_token;
  if (!token) throw new Error('Login response did not include an access token.');
  return { token, user: body?.data?.user ?? null };
}

async function fetchMe(baseUrl, token) {
  const body = await fetchJson(baseUrl, '/api/v1/auth/me', {
    headers: { authorization: `Bearer ${token}` },
  });
  return body?.data ?? null;
}

async function assertLoggedInTestIdentity(baseUrl, loginResult, {
  expectedEmail,
  allowedRoles,
  label,
}) {
  const user = loginResult.user ?? await fetchMe(baseUrl, loginResult.token);
  const expected = String(expectedEmail ?? '').trim().toLowerCase();
  const actualEmail = String(user?.email ?? '').trim().toLowerCase();
  if (!user || !allowedRoles.includes(user.role) || actualEmail !== expected) {
    throw new Error(`${label} login did not return the expected test account identity.`);
  }
  if (!String(user.name ?? '').startsWith(TEST_NAME_PREFIX)) {
    throw new Error(`${label} account display name must start with ${TEST_NAME_PREFIX}.`);
  }
  return user;
}

function guestHeaders(guestAccessToken) {
  return { 'x-guest-access-token': guestAccessToken };
}

function openCallItems(body) {
  const data = responseData(body);
  return Array.isArray(data?.items) ? data.items : [];
}

function findOpenCallItem(body, bookingNumber) {
  return openCallItems(body).find((item) => item.bookingNumber === bookingNumber) ?? null;
}

function assertNotInOpenCalls(body, bookingNumber, failMessage) {
  if (findOpenCallItem(body, bookingNumber)) {
    throw new Error(failMessage);
  }
}

async function fetchOpenCalls(baseUrl, driverToken) {
  return fetchJson(baseUrl, '/api/v1/driver/calls/open', {
    headers: { authorization: `Bearer ${driverToken}` },
  });
}

async function waitForOpenCall(baseUrl, driverToken, bookingNumber) {
  const deadline = Date.now() + OPEN_CALL_POLL_TIMEOUT_MS;
  while (Date.now() < deadline) {
    const body = await fetchOpenCalls(baseUrl, driverToken);
    const item = findOpenCallItem(body, bookingNumber);
    if (item) return item;
    await sleep(OPEN_CALL_POLL_INTERVAL_MS);
  }
  return null;
}

function assertOpenCallItemShape(item, bookingNumber, payload) {
  if (item.bookingNumber !== bookingNumber) {
    throw new Error('Open call item bookingNumber mismatch.');
  }
  if (item.serviceType?.code !== payload.serviceTypeCode) {
    throw new Error('Open call item serviceType mismatch.');
  }
  if (!item.origin || !item.destination) {
    throw new Error('Open call item is missing origin or destination.');
  }
  if (!item.scheduledPickupAt) {
    throw new Error('Open call item is missing scheduledPickupAt.');
  }
  if (!item.vehicleType?.code) {
    throw new Error('Open call item is missing vehicleType.');
  }
  if (item.amount == null || !item.currency) {
    throw new Error('Open call item is missing pricing fields.');
  }
  if (Number(item.isUrgentRequest) === 1 || item.isUrgentRequest === true) {
    throw new Error('Open call item must not be urgent.');
  }
  if (!Array.isArray(item.compatibleVehicles) || item.compatibleVehicles.length === 0) {
    throw new Error('Open call item is missing compatibleVehicles for the test driver.');
  }
}

async function fetchAdminBookingDetail(baseUrl, adminToken, bookingNumber) {
  const body = await fetchJson(baseUrl, `/api/v1/admin/bookings/${bookingNumber}`, {
    headers: { authorization: `Bearer ${adminToken}` },
  });
  return responseData(body);
}

function assertPostCreateAdminDetail(detail, bookingNumber) {
  if (detail.bookingNumber !== bookingNumber) {
    throw new Error('Admin booking detail bookingNumber mismatch.');
  }
  if (detail.status !== 'OPEN') {
    throw new Error(`Expected booking status OPEN, got ${detail.status}`);
  }
  if (detail.customer?.contactStatus !== 'PENDING') {
    throw new Error(`Expected contact_status PENDING, got ${detail.customer?.contactStatus}`);
  }
  if (detail.activeAssignment != null) {
    throw new Error('Expected no active assignment immediately after create.');
  }
  if (detail.specialRequests !== E2E_MARKER) {
    throw new Error('Admin booking detail specialRequests marker mismatch.');
  }
  if (!String(detail.customer?.name ?? '').startsWith(TEST_NAME_PREFIX)) {
    throw new Error('Admin booking detail customer name is not an E2E account.');
  }
}

function pickEnabledContactChannel(channelsPayload) {
  const channels = Array.isArray(channelsPayload?.channels) ? channelsPayload.channels : [];
  for (const code of PREFERRED_CHANNELS) {
    const match = channels.find((row) => row.code === code && row.enabled);
    if (match) return code;
  }
  const fallback = channels.find((row) => row.enabled);
  if (!fallback) {
    throw new Error('No enabled contact channel found in public settings.');
  }
  return fallback.code;
}

function assertSafeArchiveDetail(detail, record) {
  if (detail?.bookingNumber !== record.bookingNumber) {
    throw new Error(`Cleanup detail mismatch for ${record.bookingNumber}`);
  }
  if (!String(detail?.customer?.name ?? '').startsWith(TEST_NAME_PREFIX)) {
    throw new Error(`Cleanup refused non-E2E booking ${record.bookingNumber}`);
  }
  if (detail?.specialRequests !== E2E_MARKER) {
    throw new Error(`Cleanup refused booking without E2E marker ${record.bookingNumber}`);
  }
}

async function archiveCreatedBooking(baseUrl, adminToken, record) {
  const detail = await fetchAdminBookingDetail(baseUrl, adminToken, record.bookingNumber);
  assertSafeArchiveDetail(detail, record);
  const body = await fetchJson(baseUrl, '/api/v1/admin/bookings/archive', {
    method: 'POST',
    headers: { authorization: `Bearer ${adminToken}` },
    body: JSON.stringify({
      bookingNumbers: [record.bookingNumber],
      reason: E2E_MARKER,
    }),
  });
  return responseData(body);
}

function pass(message) {
  console.log(`PASS ${message}`);
}

function failStep(step, err) {
  console.error('STANDARD OPEN CALL E2E FAIL');
  console.error(`Step failed: ${step}`);
  console.error(err.message);
}

async function main() {
  const dryRun = hasArg('--dry-run');
  const { baseUrl } = assertSafeEnvironment({ dryRun });
  const payload = bookingPayload();
  assertValidPayload(payload);

  console.log(`T-Rider STANDARD open-call E2E (${dryRun ? 'dry-run' : 'live'})`);
  console.log(`Target: ${baseUrl}`);
  console.log(`Customer: ${CUSTOMER_NAME}`);
  console.log(`Marker: ${E2E_MARKER}`);

  if (dryRun) {
    console.log('Planned steps:');
    console.log('- login admin + [E2E] driver');
    console.log('- driver online');
    console.log('- create STANDARD AIRPORT_PICKUP booking (BKK -> Pattaya)');
    console.log('- assert PENDING booking hidden from /driver/calls/open');
    console.log('- start contact connection');
    console.log('- confirm sent and assert CONFIRM_REQUESTED still hidden');
    console.log('- admin verify and poll until booking appears in open calls');
    console.log('- archive booking and restore driver offline');
    console.log('Dry-run complete. No bookings were created.');
    return;
  }

  let adminToken;
  let driverToken;
  let driverWasOnline = false;
  let record = null;
  let archived = false;
  let failedStep = 'setup';

  try {
    failedStep = 'login';
    const adminLogin = await login(
      baseUrl,
      process.env.TRIDE_ADMIN_EMAIL,
      process.env.TRIDE_ADMIN_PASSWORD,
    );
    const driverLogin = await login(
      baseUrl,
      process.env.TRIDE_TEST_DRIVER_EMAIL,
      process.env.TRIDE_TEST_DRIVER_PASSWORD,
    );
    await assertLoggedInTestIdentity(baseUrl, adminLogin, {
      expectedEmail: process.env.TRIDE_ADMIN_EMAIL,
      allowedRoles: ['ADMIN', 'SUPER_ADMIN'],
      label: 'Admin',
    });
    await assertLoggedInTestIdentity(baseUrl, driverLogin, {
      expectedEmail: process.env.TRIDE_TEST_DRIVER_EMAIL,
      allowedRoles: ['DRIVER'],
      label: 'Driver',
    });
    adminToken = adminLogin.token;
    driverToken = driverLogin.token;
    pass('admin login');
    pass('driver login');

    failedStep = 'driver online';
    await fetchJson(baseUrl, '/api/v1/driver/online', {
      method: 'POST',
      headers: { authorization: `Bearer ${driverToken}` },
    });
    driverWasOnline = true;
    pass('driver online');

    const driverStatus = await fetchJson(baseUrl, '/api/v1/driver/status', {
      headers: { authorization: `Bearer ${driverToken}` },
    });
    const statusData = responseData(driverStatus);
    if (statusData?.isOnline !== true && statusData?.online !== true) {
      console.log('INFO driver status response received (online flag shape may vary).');
    }

    failedStep = 'create booking';
    await fetchJson(baseUrl, '/api/v1/bookings/pricing/calculate', {
      method: 'POST',
      body: JSON.stringify(toPricingPayload(payload)),
    });

    const created = await fetchJson(baseUrl, '/api/v1/bookings', {
      method: 'POST',
      body: JSON.stringify(payload),
    });
    const createdData = responseData(created);
    const bookingNumber = createdData?.bookingNumber;
    const guestAccessToken = createdData?.guestAccessToken;
    if (!bookingNumber) throw new Error('Booking create response did not include bookingNumber.');
    if (!guestAccessToken) throw new Error('Booking create response did not include guestAccessToken.');
    if (createdData?.isUrgentRequest) throw new Error('Created booking must not be urgent.');
    if (createdData?.contactStatus && createdData.contactStatus !== 'PENDING') {
      throw new Error(`Expected initial contactStatus PENDING, got ${createdData.contactStatus}`);
    }

    record = { bookingNumber, guestAccessToken, payload };
    pass(`booking created: ${bookingNumber}`);

    failedStep = 'assert PENDING hidden';
    const adminDetail = await fetchAdminBookingDetail(baseUrl, adminToken, bookingNumber);
    assertPostCreateAdminDetail(adminDetail, bookingNumber);
    pass('PENDING booking hidden from open calls (pre-check admin detail)');

    const openCallsAfterCreate = await fetchOpenCalls(baseUrl, driverToken);
    assertNotInOpenCalls(
      openCallsAfterCreate,
      bookingNumber,
      'STANDARD booking leaked into open calls before contact verification',
    );
    pass('PENDING booking hidden from open calls');

    failedStep = 'start contact connection';
    const channelsBody = await fetchJson(baseUrl, '/api/v1/bookings/contact-channels/public');
    const channel = pickEnabledContactChannel(responseData(channelsBody));
    record.channel = channel;

    await fetchJson(baseUrl, `/api/v1/bookings/${bookingNumber}/contact-connections`, {
      method: 'POST',
      headers: guestHeaders(guestAccessToken),
      body: JSON.stringify({ channel }),
    });
    pass(`contact connection started: ${channel}`);

    failedStep = 'confirm sent';
    await fetchJson(baseUrl, `/api/v1/bookings/${bookingNumber}/contact-connections/confirm-sent`, {
      method: 'POST',
      headers: guestHeaders(guestAccessToken),
    });

    const contactAfterConfirm = responseData(await fetchJson(
      baseUrl,
      `/api/v1/bookings/${bookingNumber}/contact-connection`,
      { headers: guestHeaders(guestAccessToken) },
    ));
    if (contactAfterConfirm?.contactStatus !== 'CONFIRM_REQUESTED') {
      throw new Error(`Expected contactStatus CONFIRM_REQUESTED, got ${contactAfterConfirm?.contactStatus}`);
    }
    pass('CONFIRM_REQUESTED booking hidden from open calls (pre-check contact state)');

    const openCallsAfterConfirm = await fetchOpenCalls(baseUrl, driverToken);
    assertNotInOpenCalls(
      openCallsAfterConfirm,
      bookingNumber,
      'STANDARD booking leaked into open calls at CONFIRM_REQUESTED',
    );
    pass('CONFIRM_REQUESTED booking hidden from open calls');

    failedStep = 'admin verify';
    const verifyBody = await fetchJson(
      baseUrl,
      `/api/v1/admin/bookings/${bookingNumber}/contact/verify`,
      {
        method: 'POST',
        headers: { authorization: `Bearer ${adminToken}` },
      },
    );
    const verifyData = responseData(verifyBody);
    if (verifyData?.contactStatus !== 'VERIFIED') {
      throw new Error(`Expected contactStatus VERIFIED after admin verify, got ${verifyData?.contactStatus}`);
    }
    pass('contact VERIFIED');

    const adminDetailAfterVerify = await fetchAdminBookingDetail(baseUrl, adminToken, bookingNumber);
    if (adminDetailAfterVerify.status !== 'OPEN') {
      throw new Error(`Expected booking status OPEN after verify, got ${adminDetailAfterVerify.status}`);
    }
    if (adminDetailAfterVerify.customer?.contactStatus !== 'VERIFIED') {
      throw new Error('Admin detail contactStatus is not VERIFIED after admin verify.');
    }
    if (verifyData?.dispatchStarted === false) {
      console.log('INFO dispatchStarted=false; polling open calls anyway in case dispatch completed asynchronously.');
    }

    failedStep = 'poll open calls';
    const openCallItem = await waitForOpenCall(baseUrl, driverToken, bookingNumber);
    if (!openCallItem) {
      throw new Error('VERIFIED STANDARD booking did not appear in driver open calls');
    }
    assertOpenCallItemShape(openCallItem, bookingNumber, payload);
    pass('VERIFIED booking visible in driver open calls');

    failedStep = 'archive booking';
    await archiveCreatedBooking(baseUrl, adminToken, record);
    archived = true;
    pass('booking archived');

    console.log('STANDARD OPEN CALL E2E PASS');
  } catch (err) {
    failStep(failedStep, err);
    process.exitCode = 1;
  } finally {
    if (record && adminToken && !archived) {
      try {
        await archiveCreatedBooking(baseUrl, adminToken, record);
        archived = true;
        pass('booking archived (cleanup)');
      } catch (cleanupErr) {
        console.error(`Cleanup archive failed: ${cleanupErr.message}`);
        process.exitCode = 1;
      }
    }

    if (driverToken && driverWasOnline) {
      try {
        await fetchJson(baseUrl, '/api/v1/driver/offline', {
          method: 'POST',
          headers: { authorization: `Bearer ${driverToken}` },
        });
        pass('driver returned offline');
      } catch (offlineErr) {
        console.error(`Driver offline cleanup failed: ${offlineErr.message}`);
        process.exitCode = 1;
      }
    }
  }
}

if (require.main === module) {
  main().catch((err) => {
    console.error('STANDARD OPEN CALL E2E FAIL');
    console.error(err.message);
    process.exit(1);
  });
}

module.exports = {
  E2E_MARKER,
  CUSTOMER_NAME,
  bookingPayload,
  assertValidPayload,
  assertNotInOpenCalls,
  assertOpenCallItemShape,
  assertPostCreateAdminDetail,
  assertSafeArchiveDetail,
  pickEnabledContactChannel,
};
