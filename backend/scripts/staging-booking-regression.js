#!/usr/bin/env node
/**
 * Safe staging booking regression runner.
 *
 * This script is intentionally gated for live staging. It never prints
 * credentials and only prints generated test booking numbers.
 */
const REGRESSION_MARKER = 'AUTOMATED_REGRESSION_TEST';
const EXPECTED_BASE_URL = 'https://trider.taxi';
const TIMEOUT_MS = Number(process.env.TRIDE_REGRESSION_TIMEOUT_MS || 15000);

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
  if (process.env.TRIDE_ALLOW_LIVE_BOOKING_REGRESSION !== '1') {
    throw new Error('Set TRIDE_ALLOW_LIVE_BOOKING_REGRESSION=1 to create staging test bookings.');
  }
  return { baseUrl };
}

function normalizeBaseUrl(value) {
  if (!value) return '';
  return String(value).trim().replace(/\/$/, '');
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
      email: 'regression@example.test',
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
      throw new Error(`${path} failed: ${message}`);
    }
    return body;
  } finally {
    clearTimeout(timer);
  }
}

async function login(baseUrl, email, password) {
  const body = await fetchJson(baseUrl, '/api/v1/auth/login', {
    method: 'POST',
    body: JSON.stringify({ email, password }),
  });
  const token = body?.data?.accessToken || body?.data?.access_token;
  if (!token) throw new Error('Login response did not include an access token.');
  return token;
}

async function main() {
  const dryRun = hasArg('--dry-run');
  const { baseUrl } = assertSafeEnvironment({ dryRun });
  const plan = scenarios();

  console.log(`T-Ride staging booking regression plan (${dryRun ? 'dry-run' : 'live'}):`);
  for (const item of plan) {
    console.log(`- ${item.label}: ${item.payload.serviceTypeCode}, ${item.payload.customer.name}`);
  }

  if (dryRun) {
    console.log('Dry-run complete. No bookings were created.');
    return;
  }

  const adminToken = await login(
    baseUrl,
    process.env.TRIDE_ADMIN_EMAIL,
    process.env.TRIDE_ADMIN_PASSWORD,
  );
  const driverToken = await login(
    baseUrl,
    process.env.TRIDE_TEST_DRIVER_EMAIL,
    process.env.TRIDE_TEST_DRIVER_PASSWORD,
  );

  const createdNumbers = [];
  try {
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
      createdNumbers.push(bookingNumber);
      await fetchJson(baseUrl, '/api/v1/public/bookings/lookup', {
        method: 'POST',
        body: JSON.stringify({
          bookingNumber,
          phone: item.payload.customer.phone,
        }),
      });
      console.log(`PASS ${item.label}: ${bookingNumber}`);
    }

    const adminList = await fetchJson(baseUrl, '/api/v1/admin/bookings', {
      headers: { authorization: `Bearer ${adminToken}` },
    });
    const listedNumbers = new Set((adminList?.data?.items || []).map((item) => item.bookingNumber));
    for (const bookingNumber of createdNumbers) {
      if (!listedNumbers.has(bookingNumber)) {
        throw new Error(`Admin list did not include ${bookingNumber}`);
      }
    }

    const first = createdNumbers[0];
    const candidates = await fetchJson(baseUrl, `/api/v1/admin/bookings/${first}/driver-candidates`, {
      headers: { authorization: `Bearer ${adminToken}` },
    });
    const candidate = (candidates?.data?.items || []).find((item) => item.eligible !== false);
    if (!candidate) {
      throw new Error('No eligible test driver candidate returned.');
    }
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

    await fetchJson(baseUrl, '/api/v1/admin/bookings/archive', {
      method: 'POST',
      headers: { authorization: `Bearer ${adminToken}` },
      body: JSON.stringify({
        bookingNumbers: createdNumbers,
        reason: REGRESSION_MARKER,
      }),
    });

    console.log(`Regression completed. Created/archived bookings: ${createdNumbers.join(', ')}`);
  } catch (err) {
    console.error(`Regression failed after bookings [${createdNumbers.join(', ')}]: ${err.message}`);
    process.exitCode = 1;
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
  assertSafeEnvironment,
  bookingPayload,
  scenarios,
  toPricingPayload,
};
