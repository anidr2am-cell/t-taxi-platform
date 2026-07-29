const { test } = require('node:test');
const assert = require('node:assert/strict');

process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const FlightService = require('../src/services/flight.service');
const AppError = require('../src/utils/AppError');
const ERROR_CODES = require('../src/constants/errorCodes');

const config = {
  apiKey: 'test-key',
  baseUrl: 'https://aerodatabox.p.rapidapi.com',
  host: 'aerodatabox.p.rapidapi.com',
  timeoutMs: 2000,
};

function providerFlight(overrides = {}) {
  return {
    number: 'TG 409',
    status: 'Expected',
    airline: {
      name: 'Thai Airways',
      iata: 'TG',
      icao: 'THA',
    },
    departure: {
      airport: {
        iata: 'BKK',
        name: 'Bangkok Suvarnabhumi',
      },
      scheduledTime: {
        utc: '2026-07-01 09:30Z',
        local: '2026-07-01 16:30+07:00',
      },
      predictedTime: {
        utc: '2026-07-01 09:40Z',
        local: '2026-07-01 16:40+07:00',
      },
      terminal: '1',
      gate: 'A1',
    },
    arrival: {
      airport: {
        iata: 'SIN',
        name: 'Singapore Changi',
      },
      scheduledTime: {
        utc: '2026-07-01 12:45Z',
        local: '2026-07-01 20:45+08:00',
      },
      predictedTime: {
        utc: '2026-07-01 13:00Z',
        local: '2026-07-01 21:00+08:00',
      },
      terminal: '2',
      gate: 'B2',
    },
    ...overrides,
  };
}

function createHttpClient(data, calls) {
  return {
    async get(url, options) {
      calls.push({ url, options });
      return { data };
    },
  };
}

test('normalizes flight number', () => {
  const service = new FlightService(config, createHttpClient([], []));

  assert.equal(service.normalizeFlightNumber('TG409'), 'TG409');
  assert.equal(service.normalizeFlightNumber(' tg 409 '), 'TG409');
  assert.equal(service.normalizeFlightNumber('tg409'), 'TG409');
  assert.equal(service.normalizeFlightNumber('7c-2203'), '7C2203');
  assert.equal(service.normalizeFlightNumber('U2 8001'), 'U28001');
  assert.equal(service.normalizeFlightNumber('THA401'), 'THA401');
});

test('invalid date validation uses INVALID_FLIGHT_DATE', () => {
  const service = new FlightService(config, createHttpClient([], []));

  assert.throws(
    () => service.normalizeFlightDate('2026-02-31'),
    (err) => err instanceof AppError && err.errorCode === ERROR_CODES.INVALID_FLIGHT_DATE,
  );
});

test('normalizes AeroDataBox UTC timestamps to ISO 8601', () => {
  const service = new FlightService(config, createHttpClient([], []));

  assert.equal(service.normalizeAeroDataBoxUtc('2026-08-01 12:10Z'), '2026-08-01T12:10:00Z');
  assert.equal(service.normalizeAeroDataBoxUtc('2026-08-01 12:10:30Z'), '2026-08-01T12:10:30Z');
  assert.equal(service.normalizeAeroDataBoxUtc(null), null);
});

test('normalizes provider response', async () => {
  const calls = [];
  const service = new FlightService(config, createHttpClient([providerFlight()], calls));

  const result = await service.search({ flightNumber: 'TG 409', flightDate: '2026-07-01' });

  assert.equal(result.flightNumber, 'TG409');
  assert.equal(result.airlineCode, 'TG');
  assert.equal(result.airlineName, 'Thai Airways');
  assert.equal(result.flightDate, '2026-07-01');
  assert.equal(result.departure.airportCode, 'BKK');
  assert.equal(result.departure.airportName, 'Bangkok Suvarnabhumi');
  assert.equal(result.departure.scheduledAt, '2026-07-01T09:30:00Z');
  assert.equal(result.departure.estimatedAt, '2026-07-01T09:40:00Z');
  assert.equal(result.departure.actualAt, null);
  assert.equal(result.arrival.airportCode, 'SIN');
  assert.equal(result.status, 'SCHEDULED');
  assert.equal(result.delayMinutes, 15);
  assert.equal(result.source, 'AERODATABOX');
  assert.match(result.retrievedAt, /^\d{4}-\d{2}-\d{2}T/);
  assert.equal(
    calls[0].url,
    'https://aerodatabox.p.rapidapi.com/flights/number/TG409/2026-07-01',
  );
  assert.equal(calls[0].options.headers['X-RapidAPI-Key'], 'test-key');
  assert.equal(calls[0].options.headers['X-RapidAPI-Host'], 'aerodatabox.p.rapidapi.com');
});

test('maps AeroDataBox provider flight statuses', () => {
  const service = new FlightService(config, createHttpClient([], []));

  assert.equal(service.mapStatus('Expected'), 'SCHEDULED');
  assert.equal(service.mapStatus('CheckIn'), 'SCHEDULED');
  assert.equal(service.mapStatus('Boarding'), 'SCHEDULED');
  assert.equal(service.mapStatus('GateClosed'), 'SCHEDULED');
  assert.equal(service.mapStatus('EnRoute'), 'ACTIVE');
  assert.equal(service.mapStatus('Departed'), 'ACTIVE');
  assert.equal(service.mapStatus('Approaching'), 'ACTIVE');
  assert.equal(service.mapStatus('Arrived'), 'LANDED');
  assert.equal(service.mapStatus('Canceled'), 'CANCELLED');
  assert.equal(service.mapStatus('Diverted'), 'DIVERTED');
  assert.equal(service.mapStatus('Delayed'), 'DELAYED');
  assert.equal(service.mapStatus('Unknown'), 'UNKNOWN');
  assert.equal(service.mapStatus('something-new'), 'UNKNOWN');
});

test('calculates delay from arrival predicted and scheduled times', () => {
  const service = new FlightService(config, createHttpClient([], []));

  assert.equal(service.calculateDelayMinutes(providerFlight()), 15);
  assert.equal(service.calculateDelayMinutes(providerFlight({
    arrival: {
      scheduledTime: { utc: '2026-07-01 12:45Z' },
      predictedTime: { utc: '2026-07-01 12:30Z' },
    },
  })), 0);
});

test('returns null delay when predicted arrival time is unavailable', () => {
  const service = new FlightService(config, createHttpClient([], []));

  assert.equal(service.calculateDelayMinutes(providerFlight({
    arrival: {
      scheduledTime: { utc: '2026-07-01 12:45Z' },
      predictedTime: undefined,
    },
  })), null);
});

test('selects deterministic matching result among multiple provider results', async () => {
  const calls = [];
  const items = [
    providerFlight({
      departure: { scheduledTime: { utc: '2026-07-01 11:00Z' } },
      arrival: { scheduledTime: { utc: '2026-07-01 14:00Z' } },
    }),
    providerFlight({
      departure: { scheduledTime: { utc: '2026-07-01 08:00Z' } },
      arrival: { scheduledTime: { utc: '2026-07-01 11:00Z' } },
    }),
    providerFlight({
      number: 'TG 410',
    }),
  ];
  const service = new FlightService(config, createHttpClient(items, calls));

  const result = await service.search({ flightNumber: 'TG409', flightDate: '2026-07-01' });

  assert.equal(result.departure.scheduledAt, '2026-07-01T08:00:00Z');
});

test('date matching uses scheduled UTC date prefix without timezone shift', async () => {
  const calls = [];
  const service = new FlightService(config, createHttpClient([
    providerFlight({
      departure: { scheduledTime: { utc: '2026-07-01 23:50Z' } },
      arrival: { scheduledTime: { utc: '2026-07-02 01:20Z' } },
    }),
  ], calls));

  const result = await service.search({ flightNumber: 'TG409', flightDate: '2026-07-01' });

  assert.equal(result.departure.scheduledAt, '2026-07-01T23:50:00Z');
});

test('flight not found returns FLIGHT_NOT_FOUND', async () => {
  const service = new FlightService(config, createHttpClient([providerFlight({
    number: 'TG 410',
  })], []));

  await assert.rejects(
    () => service.search({ flightNumber: 'TG409', flightDate: '2026-07-01' }),
    (err) => err instanceof AppError && err.errorCode === ERROR_CODES.FLIGHT_NOT_FOUND,
  );
});

test('empty provider array returns FLIGHT_NOT_FOUND', async () => {
  const service = new FlightService(config, createHttpClient([], []));

  await assert.rejects(
    () => service.search({ flightNumber: 'TG409', flightDate: '2026-07-01' }),
    (err) => err instanceof AppError && err.errorCode === ERROR_CODES.FLIGHT_NOT_FOUND,
  );
});

test('flight not found is not cached', async () => {
  const calls = [];
  const service = new FlightService(config, createHttpClient([providerFlight({
    number: 'TG 410',
  })], calls));

  await assert.rejects(
    () => service.search({ flightNumber: 'TG409', flightDate: '2026-07-01' }),
    (err) => err.errorCode === ERROR_CODES.FLIGHT_NOT_FOUND,
  );
  await assert.rejects(
    () => service.search({ flightNumber: 'TG409', flightDate: '2026-07-01' }),
    (err) => err.errorCode === ERROR_CODES.FLIGHT_NOT_FOUND,
  );

  assert.equal(calls.length, 2);
});

test('missing provider configuration returns FLIGHT_PROVIDER_NOT_CONFIGURED', async () => {
  const service = new FlightService({
    apiKey: '',
    baseUrl: config.baseUrl,
    host: config.host,
    timeoutMs: config.timeoutMs,
  }, createHttpClient([], []));

  await assert.rejects(
    () => service.search({ flightNumber: 'TG409', flightDate: '2026-07-01' }),
    (err) => err instanceof AppError
      && err.errorCode === ERROR_CODES.FLIGHT_PROVIDER_NOT_CONFIGURED,
  );
});

test('timeout maps to FLIGHT_PROVIDER_TIMEOUT', async () => {
  const service = new FlightService(config, {
    async get() {
      const err = new Error('timeout');
      err.code = 'ECONNABORTED';
      throw err;
    },
  });

  await assert.rejects(
    () => service.search({ flightNumber: 'TG409', flightDate: '2026-07-01' }),
    (err) => err instanceof AppError
      && err.errorCode === ERROR_CODES.FLIGHT_PROVIDER_TIMEOUT,
  );
});

test('rate limit maps to FLIGHT_PROVIDER_RATE_LIMITED', async () => {
  const service = new FlightService(config, {
    async get() {
      throw { response: { status: 429, data: {} } };
    },
  });

  await assert.rejects(
    () => service.search({ flightNumber: 'TG409', flightDate: '2026-07-01' }),
    (err) => err instanceof AppError
      && err.errorCode === ERROR_CODES.FLIGHT_PROVIDER_RATE_LIMITED,
  );
});

test('cache hit avoids a second provider request', async () => {
  const calls = [];
  const service = new FlightService(config, createHttpClient([providerFlight()], calls));

  await service.search({ flightNumber: 'TG409', flightDate: '2026-07-01' });
  await service.search({ flightNumber: 'TG 409', flightDate: '2026-07-01' });

  assert.equal(calls.length, 1);
});

test('cached values cannot be mutated by callers', async () => {
  const calls = [];
  const service = new FlightService(config, createHttpClient([providerFlight()], calls));

  const first = await service.search({ flightNumber: 'TG409', flightDate: '2026-07-01' });
  first.arrival.airportCode = 'MUTATED';

  const second = await service.search({ flightNumber: 'TG409', flightDate: '2026-07-01' });

  assert.equal(calls.length, 1);
  assert.equal(second.arrival.airportCode, 'SIN');
});

test('provider errors are not cached', async () => {
  const calls = [];
  const service = new FlightService(config, {
    async get() {
      calls.push({});
      throw { response: { status: 500, data: {} } };
    },
  });

  await assert.rejects(
    () => service.search({ flightNumber: 'TG409', flightDate: '2026-07-01' }),
    (err) => err.errorCode === ERROR_CODES.FLIGHT_PROVIDER_ERROR,
  );
  await assert.rejects(
    () => service.search({ flightNumber: 'TG409', flightDate: '2026-07-01' }),
    (err) => err.errorCode === ERROR_CODES.FLIGHT_PROVIDER_ERROR,
  );

  assert.equal(calls.length, 2);
});
