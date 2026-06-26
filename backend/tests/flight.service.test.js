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
  baseUrl: 'https://example.test',
  timeoutMs: 2000,
};

function providerFlight(overrides = {}) {
  return {
    flight_date: '2026-07-01',
    flight_status: 'scheduled',
    airline: {
      name: 'Thai Airways',
      iata: 'TG',
      icao: 'THA',
    },
    flight: {
      number: '409',
      iata: 'TG409',
      icao: 'THA409',
    },
    departure: {
      airport: 'Suvarnabhumi Airport',
      iata: 'BKK',
      scheduled: '2026-07-01T09:30:00+00:00',
      estimated: '2026-07-01T09:40:00+00:00',
      actual: null,
      terminal: '1',
      gate: 'A1',
      delay: 10,
    },
    arrival: {
      airport: 'Singapore Changi Airport',
      iata: 'SIN',
      scheduled: '2026-07-01T12:45:00+00:00',
      estimated: '2026-07-01T13:00:00+00:00',
      actual: null,
      terminal: '2',
      gate: 'B2',
      delay: 15,
    },
    ...overrides,
  };
}

function createHttpClient(data, calls) {
  return {
    async get(url, options) {
      calls.push({ url, options });
      return { data: { data } };
    },
  };
}

test('normalizes flight number', () => {
  const service = new FlightService(config, createHttpClient([], []));

  assert.equal(service.normalizeFlightNumber('TG409'), 'TG409');
  assert.equal(service.normalizeFlightNumber(' tg 409 '), 'TG409');
  assert.equal(service.normalizeFlightNumber('tg409'), 'TG409');
});

test('invalid date validation uses INVALID_FLIGHT_DATE', () => {
  const service = new FlightService(config, createHttpClient([], []));

  assert.throws(
    () => service.normalizeFlightDate('2026-02-31'),
    (err) => err instanceof AppError && err.errorCode === ERROR_CODES.INVALID_FLIGHT_DATE,
  );
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
  assert.equal(result.arrival.airportCode, 'SIN');
  assert.equal(result.status, 'SCHEDULED');
  assert.equal(result.delayMinutes, 15);
  assert.equal(result.source, 'AVIATIONSTACK');
  assert.match(result.retrievedAt, /^\d{4}-\d{2}-\d{2}T/);
  assert.equal(calls[0].options.params.access_key, 'test-key');
  assert.equal(calls[0].options.params.flight_iata, 'TG409');
  assert.equal(calls[0].options.params.flight_date, '2026-07-01');
});

test('maps provider flight statuses', () => {
  const service = new FlightService(config, createHttpClient([], []));

  assert.equal(service.mapStatus('active'), 'ACTIVE');
  assert.equal(service.mapStatus('landed'), 'LANDED');
  assert.equal(service.mapStatus('cancelled'), 'CANCELLED');
  assert.equal(service.mapStatus('diverted'), 'DIVERTED');
  assert.equal(service.mapStatus('delayed'), 'DELAYED');
  assert.equal(service.mapStatus('something-new'), 'UNKNOWN');
});

test('calculates delay from arrival estimate and never returns negative', () => {
  const service = new FlightService(config, createHttpClient([], []));

  assert.equal(service.calculateDelayMinutes(providerFlight()), 15);
  assert.equal(service.calculateDelayMinutes(providerFlight({
    arrival: {
      scheduled: '2026-07-01T12:45:00+00:00',
      estimated: '2026-07-01T12:30:00+00:00',
    },
  })), 0);
});

test('uses provider delay when estimated arrival is unavailable', () => {
  const service = new FlightService(config, createHttpClient([], []));

  assert.equal(service.calculateDelayMinutes(providerFlight({
    arrival: {
      scheduled: '2026-07-01T12:45:00+00:00',
      estimated: null,
      delay: 22,
    },
  })), 22);
});

test('selects deterministic matching result among multiple provider results', async () => {
  const calls = [];
  const items = [
    providerFlight({
      flight_date: '2026-07-01',
      departure: { scheduled: '2026-07-01T11:00:00+00:00' },
      arrival: { scheduled: '2026-07-01T14:00:00+00:00' },
    }),
    providerFlight({
      flight_date: '2026-07-01',
      departure: { scheduled: '2026-07-01T08:00:00+00:00' },
      arrival: { scheduled: '2026-07-01T11:00:00+00:00' },
    }),
    providerFlight({
      flight_date: '2026-07-01',
      flight: { iata: 'TG410', number: '410' },
    }),
  ];
  const service = new FlightService(config, createHttpClient(items, calls));

  const result = await service.search({ flightNumber: 'TG409', flightDate: '2026-07-01' });

  assert.equal(result.departure.scheduledAt, '2026-07-01T08:00:00+00:00');
});

test('date matching uses provider date text without UTC date shift', async () => {
  const calls = [];
  const service = new FlightService(config, createHttpClient([
    providerFlight({
      flight_date: '2026-07-01',
      departure: { scheduled: '2026-07-01T23:50:00-10:00' },
      arrival: { scheduled: '2026-07-02T01:20:00-10:00' },
    }),
  ], calls));

  const result = await service.search({ flightNumber: 'TG409', flightDate: '2026-07-01' });

  assert.equal(result.departure.scheduledAt, '2026-07-01T23:50:00-10:00');
});

test('flight not found returns FLIGHT_NOT_FOUND', async () => {
  const service = new FlightService(config, createHttpClient([providerFlight({
    flight: { iata: 'TG410', number: '410' },
  })], []));

  await assert.rejects(
    () => service.search({ flightNumber: 'TG409', flightDate: '2026-07-01' }),
    (err) => err instanceof AppError && err.errorCode === ERROR_CODES.FLIGHT_NOT_FOUND,
  );
});

test('flight not found is not cached', async () => {
  const calls = [];
  const service = new FlightService(config, createHttpClient([providerFlight({
    flight: { iata: 'TG410', number: '410' },
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
