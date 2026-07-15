#!/usr/bin/env node
/**
 * Safe staging booking regression runner.
 *
 * This script is intentionally gated for live staging. It never prints
 * credentials and only prints generated test booking numbers.
 */
const REGRESSION_MARKER = 'AUTOMATED_REGRESSION_TEST';
const EXPECTED_BASE_URL = 'https://trider.taxi';
const TEST_NAME_PREFIX = '[E2E]';
const TIMEOUT_MS = Number(process.env.TRIDE_REGRESSION_TIMEOUT_MS || 15000);
const ADMIN_LIST_PAGE_LIMIT = 20;
const ADMIN_LIST_MAX_PAGES = 10;
const { loginSchema } = require('../src/validators/auth.validator');
const { createBookingSchema } = require('../src/validators/booking.validator');

function hasArg(name) {
  return process.argv.slice(2).includes(name);
}

function assertSafeEnvironment({ dryRun }) {
  const baseUrl = normalizeBaseUrl(process.env.TRIDE_BASE_URL);
  if (!baseUrl) {
    throw new Error('TRIDE_BASE_URL is required.');
  }
  if (baseUrl !== EXPECTED_BASE_URL) {
    throw new Error(`Refusing to run outside ${EXPECTED_BASE_URL}.`);
  }
  if (dryRun) return { baseUrl };

  const required = [
    'TRIDE_ADMIN_EMAIL',
    'TRIDE_ADMIN_PASSWORD',
    'TRIDE_TEST_DRIVER_EMAIL',
    'TRIDE_TEST_DRIVER_PASSWORD',
  ];
  const missing = required.filter((name) => !process.env[name]);
  if (missing.length) {
    throw new Error(`Missing required environment variables: ${missing.join(', ')}`);
  }
  assertEmailEnv('TRIDE_ADMIN_EMAIL');
  assertEmailEnv('TRIDE_TEST_DRIVER_EMAIL');
  if (
    process.env.TRIDE_TEST_ADMIN_EMAIL &&
    normalizeEmail(process.env.TRIDE_TEST_ADMIN_EMAIL) !== normalizeEmail(process.env.TRIDE_ADMIN_EMAIL)
  ) {
    throw new Error('TRIDE_ADMIN_EMAIL must match TRIDE_TEST_ADMIN_EMAIL for staging regression.');
  }
  if (process.env.TRIDE_ALLOW_LIVE_BOOKING_REGRESSION !== '1') {
    throw new Error('Set TRIDE_ALLOW_LIVE_BOOKING_REGRESSION=1 to create staging test bookings.');
  }
  return { baseUrl };
}

function normalizeBaseUrl(value) {
  if (!value) return '';
  return String(value).trim().replace(/\/$/, '');
}

function normalizeEmail(value) {
  return String(value ?? '').trim().toLowerCase();
}

function isValidEmail(value) {
  const { error } = loginSchema.validate({ email: normalizeEmail(value), password: 'validation-only' });
  return !error;
}

function assertEmailEnv(name) {
  if (!isValidEmail(process.env[name])) {
    throw new Error(`${name} must be a valid email address.`);
  }
}

function futurePickup(offsetDays = 7) {
  const date = new Date();
  date.setUTCDate(date.getUTCDate() + offsetDays);
  date.setUTCHours(3, 30, 0, 0);
  return date.toISOString();
}

function scenarios() {
  return [
    {
      label: 'airport pickup ko 7C',
      payload: bookingPayload({
        customerName: '[E2E] 박용세',
        flightNumber: '7C2203',
      }),
    },
    {
      label: 'airport pickup th TG',
      payload: bookingPayload({
        customerName: '[E2E] สมชาย ทดสอบ',
        flightNumber: 'TG401',
      }),
    },
    {
      label: 'airport pickup en no flight',
      payload: bookingPayload({
        customerName: '[E2E] John Regression',
        flightNumber: null,
      }),
    },
    {
      label: 'airport dropoff no flight',
      payload: bookingPayload({
        serviceTypeCode: 'AIRPORT_DROPOFF',
        customerName: '[E2E] Airport Dropoff',
        flightNumber: null,
      }),
    },
    {
      label: 'city transfer',
      payload: bookingPayload({
        serviceTypeCode: 'CITY_TRANSFER',
        customerName: '[E2E] City Transfer',
        flightNumber: null,
      }),
    },
  ];
}

function bookingPayload({
  serviceTypeCode = 'AIRPORT_PICKUP',
  customerName,
  flightNumber,
}) {
  const common = {
    serviceTypeCode,
    vehicleTypeCode: 'SUV',
    vehicleCount: 1,
    scheduledPickupAt: futurePickup(),
    passengers: { adults: 2, children: 0, infants: 0 },
    luggage: { carriers20Inch: 1, carriers24InchPlus: 1, golfBags: 0 },
    options: { nameSign: serviceTypeCode === 'AIRPORT_PICKUP' },
    customer: {
      name: customerName,
      phone: '+66000000001',
      email: 'regression@example.com',
      countryCode: 'TH',
    },
    additionalRequests: REGRESSION_MARKER,
  };

  if (serviceTypeCode === 'AIRPORT_DROPOFF') {
    return {
      ...common,
      origin: { name: 'Pattaya', address: 'Pattaya, Chon Buri, Thailand', placeId: 'staging-pattaya' },
      destination: { name: 'Suvarnabhumi Airport', address: 'Suvarnabhumi Airport, Bangkok, Thailand', placeId: 'staging-bkk' },
      originLocationCode: 'PATTAYA',
      destinationLocationCode: 'BKK',
      transfer: { airportIata: 'BKK', flightNumber: null },
    };
  }

  if (serviceTypeCode === 'CITY_TRANSFER') {
    return {
      ...common,
      origin: { name: 'Bangkok', address: 'Bangkok, Thailand', placeId: 'staging-bangkok' },
      destination: { name: 'Pattaya', address: 'Pattaya, Chon Buri, Thailand', placeId: 'staging-pattaya' },
      originLocationCode: 'BANGKOK',
      destinationLocationCode: 'PATTAYA',
    };
  }

  return {
    ...common,
    origin: { name: 'Suvarnabhumi Airport', address: 'Suvarnabhumi Airport, Bangkok, Thailand', placeId: 'staging-bkk' },
    destination: { name: 'Pattaya', address: 'Pattaya, Chon Buri, Thailand', placeId: 'staging-pattaya' },
    originAirportIata: 'BKK',
    destinationLocationCode: 'PATTAYA',
    transfer: { airportIata: 'BKK', flightNumber },
  };
}

function formatValidationErrors(errors) {
  return errors
    .map((item) => [item.field, item.type, item.source].filter(Boolean).join(':'))
    .filter(Boolean)
    .join(', ');
}

function assertValidBookingPayload(payload, label) {
  const { error } = createBookingSchema.validate(payload, {
    abortEarly: false,
    stripUnknown: false,
  });
  if (!error) return;
  const errors = error.details.map((detail) => ({
    field: detail.path.join('.'),
    type: detail.type,
    source: 'body',
  }));
  const suffix = formatValidationErrors(errors);
  throw new Error(`${label} booking payload is invalid${suffix ? ` (${suffix})` : ''}`);
}

function assertValidScenarioPayloads(plan) {
  for (const item of plan) {
    assertValidBookingPayload(item.payload, item.label);
  }
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

function responseData(body) {
  return body?.data ?? body;
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

function isTestIdentity(user, expectedEmail, expectedRole) {
  return (
    user?.role === expectedRole &&
    String(user?.email ?? '').trim().toLowerCase() === String(expectedEmail ?? '').trim().toLowerCase() &&
    String(user?.name ?? '').startsWith(TEST_NAME_PREFIX)
  );
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

function candidateItems(payload) {
  const data = payload?.data ?? {};
  if (Array.isArray(data.items)) return data.items;
  if (Array.isArray(data.candidates)) return data.candidates;
  return [];
}

function selectTestDriverCandidate(payload, driverUser) {
  const candidates = candidateItems(payload);
  const candidate = candidates.find((item) => (
    item.eligible !== false &&
    String(item.displayName ?? '').startsWith(TEST_NAME_PREFIX) &&
    String(item.displayName ?? '') === String(driverUser.name ?? '')
  ));
  if (!candidate) {
    throw new Error('Expected test driver was not returned as an eligible candidate.');
  }
  return candidate;
}

function serviceDateFromPayload(payload) {
  return String(payload.scheduledPickupAt ?? '').slice(0, 10);
}

function buildQuery(params) {
  const query = new URLSearchParams();
  for (const [key, value] of Object.entries(params)) {
    if (value != null && value !== '') query.set(key, String(value));
  }
  return query.toString();
}

async function findCreatedBookingInAdminList(baseUrl, adminToken, record) {
  const serviceDate = serviceDateFromPayload(record.payload);
  for (let page = 1; page <= ADMIN_LIST_MAX_PAGES; page += 1) {
    const query = buildQuery({
      view: 'all',
      search: record.bookingNumber,
      serviceDateFrom: serviceDate,
      serviceDateTo: serviceDate,
      page,
      limit: ADMIN_LIST_PAGE_LIMIT,
    });
    const body = await fetchJson(baseUrl, `/api/v1/admin/bookings?${query}`, {
      headers: { authorization: `Bearer ${adminToken}` },
    });
    const data = responseData(body);
    const items = Array.isArray(data?.items) ? data.items : [];
    const found = items.find((item) => item.bookingNumber === record.bookingNumber);
    if (found) return found;
    const total = Number(data?.total ?? items.length);
    const pageSize = Number(data?.pageSize ?? ADMIN_LIST_PAGE_LIMIT);
    if (!Number.isFinite(total) || !Number.isFinite(pageSize) || page * pageSize >= total) {
      break;
    }
  }
  return null;
}

async function assertAdminListIncludesCreatedBookings(baseUrl, adminToken, records) {
  for (const record of records) {
    const item = await findCreatedBookingInAdminList(baseUrl, adminToken, record);
    if (!item) {
      throw new Error(`Admin list did not include ${record.bookingNumber}`);
    }
  }
}

function assertSafeRegressionBookingDetail(detail, record) {
  const data = responseData(detail);
  if (data?.bookingNumber !== record.bookingNumber) {
    throw new Error(`Cleanup detail mismatch for ${record.bookingNumber}`);
  }
  if (!String(data?.customer?.name ?? '').startsWith(TEST_NAME_PREFIX)) {
    throw new Error(`Cleanup refused non-E2E booking ${record.bookingNumber}`);
  }
  if (data?.specialRequests !== REGRESSION_MARKER) {
    throw new Error(`Cleanup refused booking without regression marker ${record.bookingNumber}`);
  }
}

async function archiveCreatedRegressionBookings(baseUrl, adminToken, records) {
  if (!records.length) return { archived: 0 };
  for (const record of records) {
    const detail = await fetchJson(baseUrl, `/api/v1/admin/bookings/${record.bookingNumber}`, {
      headers: { authorization: `Bearer ${adminToken}` },
    });
    assertSafeRegressionBookingDetail(detail, record);
  }
  const body = await fetchJson(baseUrl, '/api/v1/admin/bookings/archive', {
    method: 'POST',
    headers: { authorization: `Bearer ${adminToken}` },
    body: JSON.stringify({
      bookingNumbers: records.map((record) => record.bookingNumber),
      reason: REGRESSION_MARKER,
    }),
  });
  return responseData(body);
}

async function main() {
  const dryRun = hasArg('--dry-run');
  const { baseUrl } = assertSafeEnvironment({ dryRun });
  const plan = scenarios();
  assertValidScenarioPayloads(plan);

  console.log(`T-Ride staging booking regression plan (${dryRun ? 'dry-run' : 'live'}):`);
  for (const item of plan) {
    console.log(`- ${item.label}: ${item.payload.serviceTypeCode}, ${item.payload.customer.name}`);
  }

  if (dryRun) {
    console.log('Dry-run complete. No bookings were created.');
    return;
  }

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
  const adminUser = await assertLoggedInTestIdentity(baseUrl, adminLogin, {
    expectedEmail: process.env.TRIDE_ADMIN_EMAIL,
    allowedRoles: ['ADMIN', 'SUPER_ADMIN'],
    label: 'Admin',
  });
  const driverUser = await assertLoggedInTestIdentity(baseUrl, driverLogin, {
    expectedEmail: process.env.TRIDE_TEST_DRIVER_EMAIL,
    allowedRoles: ['DRIVER'],
    label: 'Driver',
  });
  const adminToken = adminLogin.token;
  const driverToken = driverLogin.token;

  const createdRecords = [];
  let archivedCreatedBookings = false;
  let driverWasPreparedOnline = false;
  try {
    await fetchJson(baseUrl, '/api/v1/driver/online', {
      method: 'POST',
      headers: { authorization: `Bearer ${driverToken}` },
    });
    driverWasPreparedOnline = true;

    for (const item of plan) {
      await fetchJson(baseUrl, '/api/v1/bookings/pricing/calculate', {
        method: 'POST',
        body: JSON.stringify(toPricingPayload(item.payload)),
      });
      const created = await fetchJson(baseUrl, '/api/v1/bookings', {
        method: 'POST',
        body: JSON.stringify(item.payload),
      });
      const bookingNumber = created?.data?.bookingNumber;
      if (!bookingNumber) throw new Error(`${item.label} did not return bookingNumber`);
      createdRecords.push({ bookingNumber, label: item.label, payload: item.payload });
      await fetchJson(baseUrl, '/api/v1/public/bookings/lookup', {
        method: 'POST',
        body: JSON.stringify({
          bookingNumber,
          phone: item.payload.customer.phone,
        }),
      });
      console.log(`PASS ${item.label}: ${bookingNumber}`);
    }

    await assertAdminListIncludesCreatedBookings(baseUrl, adminToken, createdRecords);

    const first = createdRecords[0].bookingNumber;
    const candidates = await fetchJson(baseUrl, `/api/v1/admin/bookings/${first}/driver-candidates`, {
      headers: { authorization: `Bearer ${adminToken}` },
    });
    const candidate = selectTestDriverCandidate(candidates, driverUser);
    await fetchJson(baseUrl, `/api/v1/admin/bookings/${first}/assign-driver`, {
      method: 'POST',
      headers: { authorization: `Bearer ${adminToken}` },
      body: JSON.stringify({
        driverId: candidate.driverId,
        assignmentReason: REGRESSION_MARKER,
      }),
    });
    await fetchJson(baseUrl, '/api/v1/driver/bookings/today', {
      headers: { authorization: `Bearer ${driverToken}` },
    });

    for (const action of ['start-route', 'arrive', 'mark-picked-up', 'end-trip']) {
      await fetchJson(baseUrl, `/api/v1/driver/bookings/${first}/${action}`, {
        method: 'POST',
        headers: { authorization: `Bearer ${driverToken}` },
      });
    }

    await archiveCreatedRegressionBookings(baseUrl, adminToken, createdRecords);
    archivedCreatedBookings = true;

    console.log(`Regression completed. Created/archived bookings: ${createdRecords.map((record) => record.bookingNumber).join(', ')}`);
    console.log(`Regression admin: ${adminUser.email}`);
    console.log(`Regression driver: ${driverUser.email}`);
  } catch (err) {
    console.error(`Regression failed after bookings [${createdRecords.map((record) => record.bookingNumber).join(', ')}]: ${err.message}`);
    process.exitCode = 1;
    if (createdRecords.length && !archivedCreatedBookings) {
      try {
        const cleanup = await archiveCreatedRegressionBookings(baseUrl, adminToken, createdRecords);
        archivedCreatedBookings = true;
        console.log(`Regression cleanup archived bookings: ${createdRecords.map((record) => record.bookingNumber).join(', ')} (${cleanup?.archived ?? createdRecords.length})`);
      } catch (cleanupErr) {
        console.error(`Regression cleanup archive failed: ${cleanupErr.message}`);
        process.exitCode = 1;
      }
    }
  } finally {
    if (driverWasPreparedOnline) {
      try {
        await fetchJson(baseUrl, '/api/v1/driver/offline', {
          method: 'POST',
          headers: { authorization: `Bearer ${driverToken}` },
        });
        console.log('Regression driver returned offline.');
      } catch (err) {
        console.error(`Regression driver offline cleanup failed: ${err.message}`);
        process.exitCode = 1;
      }
    }
  }
}

function toPricingPayload(payload) {
  return {
    serviceTypeCode: payload.serviceTypeCode,
    vehicleTypeCode: payload.vehicleTypeCode,
    vehicleCount: payload.vehicleCount,
    scheduledPickupAt: payload.scheduledPickupAt,
    originAirportIata: payload.originAirportIata,
    originLocationCode: payload.originLocationCode,
    destinationLocationCode: payload.destinationLocationCode,
    destinationRegion: payload.destinationRegion,
    options: payload.options,
    passengers: payload.passengers,
    luggage: payload.luggage,
  };
}

if (require.main === module) {
  main().catch((err) => {
    console.error(err.message);
    process.exit(1);
  });
}

module.exports = {
  REGRESSION_MARKER,
  TEST_NAME_PREFIX,
  assertSafeEnvironment,
  bookingPayload,
  candidateItems,
  formatHttpError,
  assertValidBookingPayload,
  assertValidScenarioPayloads,
  assertAdminListIncludesCreatedBookings,
  archiveCreatedRegressionBookings,
  findCreatedBookingInAdminList,
  isValidEmail,
  isTestIdentity,
  normalizeEmail,
  selectTestDriverCandidate,
  scenarios,
  toPricingPayload,
};
