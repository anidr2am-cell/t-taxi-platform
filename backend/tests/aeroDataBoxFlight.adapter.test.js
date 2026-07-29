const { test } = require('node:test');
const assert = require('node:assert/strict');

const AeroDataBoxFlightAdapter = require('../src/adapters/aeroDataBoxFlight.adapter');
const AppError = require('../src/utils/AppError');
const ERROR_CODES = require('../src/constants/errorCodes');

const config = {
  apiKey: 'test-key',
  baseUrl: 'https://aerodatabox.p.rapidapi.com',
  host: 'aerodatabox.p.rapidapi.com',
  timeoutMs: 2000,
};

function createHttpClient(responseData, calls) {
  return {
    async get(url, options) {
      calls.push({ url, options });
      return { data: responseData };
    },
  };
}

test('isConfigured requires apiKey and host', () => {
  const adapter = new AeroDataBoxFlightAdapter(config, createHttpClient([], []));

  assert.equal(adapter.isConfigured(), true);
  assert.equal(new AeroDataBoxFlightAdapter({
    ...config,
    apiKey: '',
  }).isConfigured(), false);
  assert.equal(new AeroDataBoxFlightAdapter({
    ...config,
    host: '',
  }).isConfigured(), false);
});

test('fetchFlights calls correct URL and headers', async () => {
  const calls = [];
  const adapter = new AeroDataBoxFlightAdapter(
    config,
    createHttpClient([{ number: 'TG 401' }], calls),
  );

  const result = await adapter.fetchFlights('TG401', '2026-08-01');

  assert.deepEqual(result, [{ number: 'TG 401' }]);
  assert.equal(
    calls[0].url,
    'https://aerodatabox.p.rapidapi.com/flights/number/TG401/2026-08-01',
  );
  assert.equal(calls[0].options.timeout, 2000);
  assert.equal(calls[0].options.headers['X-RapidAPI-Key'], 'test-key');
  assert.equal(calls[0].options.headers['X-RapidAPI-Host'], 'aerodatabox.p.rapidapi.com');
});

test('fetchFlights encodes flight number in URL path', async () => {
  const calls = [];
  const adapter = new AeroDataBoxFlightAdapter(
    config,
    createHttpClient([], calls),
  );

  await adapter.fetchFlights('U2 8001', '2026-07-01');

  assert.equal(
    calls[0].url,
    'https://aerodatabox.p.rapidapi.com/flights/number/U2%208001/2026-07-01',
  );
});

test('fetchFlights returns empty array without error', async () => {
  const adapter = new AeroDataBoxFlightAdapter(
    config,
    createHttpClient([], []),
  );

  const result = await adapter.fetchFlights('TG999', '2026-07-01');

  assert.deepEqual(result, []);
});

test('fetchFlights throws when provider is not configured', async () => {
  const adapter = new AeroDataBoxFlightAdapter({
    apiKey: '',
    baseUrl: config.baseUrl,
    host: config.host,
    timeoutMs: config.timeoutMs,
  });

  await assert.rejects(
    () => adapter.fetchFlights('TG401', '2026-08-01'),
    (err) => err instanceof AppError
      && err.errorCode === ERROR_CODES.FLIGHT_PROVIDER_NOT_CONFIGURED,
  );
});

test('fetchFlights throws on malformed non-array response', async () => {
  const adapter = new AeroDataBoxFlightAdapter(
    config,
    createHttpClient({ flights: [] }, []),
  );

  await assert.rejects(
    () => adapter.fetchFlights('TG401', '2026-08-01'),
    (err) => err instanceof AppError
      && err.errorCode === ERROR_CODES.FLIGHT_PROVIDER_ERROR,
  );
});

test('mapProviderError maps timeout to FLIGHT_PROVIDER_TIMEOUT', () => {
  const adapter = new AeroDataBoxFlightAdapter(config);
  const err = new Error('timeout');
  err.code = 'ETIMEDOUT';

  const mapped = adapter.mapProviderError(err);

  assert.equal(mapped.errorCode, ERROR_CODES.FLIGHT_PROVIDER_TIMEOUT);
});

test('mapProviderError maps 401 and 403 to FLIGHT_PROVIDER_NOT_CONFIGURED', () => {
  const adapter = new AeroDataBoxFlightAdapter(config);

  assert.equal(
    adapter.mapProviderError({ response: { status: 401 } }).errorCode,
    ERROR_CODES.FLIGHT_PROVIDER_NOT_CONFIGURED,
  );
  assert.equal(
    adapter.mapProviderError({ response: { status: 403 } }).errorCode,
    ERROR_CODES.FLIGHT_PROVIDER_NOT_CONFIGURED,
  );
});

test('mapProviderError maps 429 to FLIGHT_PROVIDER_RATE_LIMITED', () => {
  const adapter = new AeroDataBoxFlightAdapter(config);

  const mapped = adapter.mapProviderError({ response: { status: 429 } });

  assert.equal(mapped.errorCode, ERROR_CODES.FLIGHT_PROVIDER_RATE_LIMITED);
});

test('mapProviderError maps other HTTP errors to FLIGHT_PROVIDER_ERROR', () => {
  const adapter = new AeroDataBoxFlightAdapter(config);

  const mapped = adapter.mapProviderError({ response: { status: 500 } });

  assert.equal(mapped.errorCode, ERROR_CODES.FLIGHT_PROVIDER_ERROR);
});
