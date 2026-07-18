const test = require('node:test');
const assert = require('node:assert/strict');
const {
  E2E_MARKER,
  FixturePreparationError,
  FixtureRegistry,
  HARD_ALLOWED_HOSTS,
  NetworkAudit,
  TEST_NAME_PREFIX,
  assertCleanupCandidate,
  assertNoTokenInUrl,
  assertServerCleanupCandidate,
  assertUrlAllowed,
  buildBookingPayload,
  buildConfig,
  classifyNetworkUrl,
  createRunId,
  createViewportRunId,
  redact,
  redactString,
  sanitizeUrl,
  serializeSafeError,
  tokenFingerprint,
} = require('./core');
const {
  cleanupPendingFixtures,
  prepareFixture,
} = require('./run');

const stagingEnv = {
  TRIDE_E2E_TARGET: 'staging',
  TRIDE_E2E_FRONTEND_URL: 'https://trider.taxi',
  TRIDE_E2E_BACKEND_URL: 'https://trider.taxi',
};

function liveEnv(overrides = {}) {
  return {
    ...stagingEnv,
    TRIDE_E2E_ADMIN_EMAIL: 'tride.e2e.admin@example.com',
    TRIDE_E2E_ADMIN_PASSWORD: 'local-only',
    TRIDE_E2E_DRIVER_EMAIL: 'tride.e2e.driver@example.com',
    TRIDE_E2E_DRIVER_PASSWORD: 'local-only',
    TRIDE_E2E_DRIVER_ID: '12',
    TRIDE_E2E_CUSTOMER_PHONE: '+66000000001',
    TRIDE_E2E_ALLOW_LIVE: '1',
    ...overrides,
  };
}

function cleanupFixture(overrides = {}) {
  const runId = overrides.runId || 'E2E-20260718T010203-abcd-360';
  return {
    runId,
    bookingNumber: 'TX202607180001',
    customerName: `[E2E] Customer ${runId}`,
    marker: `${E2E_MARKER} ${runId}`,
    ...overrides,
  };
}

function serverBooking(fixture, overrides = {}) {
  return {
    bookingNumber: fixture.bookingNumber,
    customer: { name: fixture.customerName },
    specialRequests: fixture.marker,
    ...overrides,
  };
}

test('hard allowed hosts accept only staging and localhost defaults', () => {
  assert.deepEqual([...HARD_ALLOWED_HOSTS].sort(), ['127.0.0.1', 'localhost', 'trider.taxi']);
  assert.equal(assertUrlAllowed('url', 'https://trider.taxi/'), 'https://trider.taxi');
  assert.equal(assertUrlAllowed('url', 'http://127.0.0.1:3101'), 'http://127.0.0.1:3101');
  assert.equal(assertUrlAllowed('url', 'http://localhost:3101'), 'http://localhost:3101');
});

test('production, unknown, protocol, credential, and env whitelist bypasses are blocked', () => {
  assert.throws(() => assertUrlAllowed('url', 'https://88taxi.net'), /blocked host/);
  assert.throws(() => assertUrlAllowed('url', 'https://ktaxi.example'), /blocked host/);
  assert.throws(() => assertUrlAllowed('url', 'https://trider-production.example'), /blocked host/);
  assert.throws(() => assertUrlAllowed('url', 'https://example.com'), /hard-allowed/);
  assert.throws(() => assertUrlAllowed('url', 'ftp://trider.taxi'), /http or https/);
  assert.throws(() => assertUrlAllowed('url', 'https://user:pass@trider.taxi'), /credentials/);
  assert.throws(() => buildConfig({
    ...stagingEnv,
    TRIDE_E2E_BACKEND_URL: 'https://example.com',
    TRIDE_E2E_ALLOWED_HOSTS: 'example.com',
  }), /hard-allowed/);
});

test('config requires staging target, split host opt-in, and live variables only for live mode', () => {
  const dry = buildConfig(stagingEnv);
  assert.equal(dry.frontendUrl, 'https://trider.taxi');
  assert.throws(() => buildConfig({ ...stagingEnv, TRIDE_E2E_TARGET: 'production' }), /TARGET=staging/);
  assert.throws(() => buildConfig({
    ...stagingEnv,
    TRIDE_E2E_FRONTEND_URL: 'https://trider.taxi',
    TRIDE_E2E_BACKEND_URL: 'http://localhost:3101',
  }), /hosts must match/);
  assert.equal(buildConfig({
    ...stagingEnv,
    TRIDE_E2E_FRONTEND_URL: 'https://trider.taxi',
    TRIDE_E2E_BACKEND_URL: 'http://localhost:3101',
    TRIDE_E2E_ALLOW_SPLIT_HOSTS: '1',
  }).backendHost, 'localhost');
  assert.throws(() => buildConfig(stagingEnv, { requireSecrets: true }), /Missing live E2E variables/);
  assert.throws(() => buildConfig(liveEnv({ TRIDE_E2E_DRIVER_ID: 'abc' }), { requireSecrets: true }), /DRIVER_ID/);
  assert.throws(() => buildConfig(liveEnv({ TRIDE_E2E_ALLOW_LIVE: '0' }), { requireSecrets: true }), /ALLOW_LIVE/);
});

test('token redaction removes nested secrets and serializes errors safely', () => {
  const sampleToken = 'abc123456789012345678901234567890xyz';
  const redacted = redact({
    guestAccessToken: sampleToken,
    nested: { Authorization: `Bearer ${sampleToken}` },
    response: { body: { token: sampleToken } },
    safe: 'hello',
  });
  assert.equal(redacted.guestAccessToken, '[REDACTED]');
  assert.equal(redacted.nested.Authorization, '[REDACTED]');
  assert.equal(redacted.response.body.token, '[REDACTED]');
  assert.equal(redacted.safe, 'hello');
  assert.equal(redactString(`Bearer ${sampleToken}`), 'Bearer [REDACTED]');
  const safeError = serializeSafeError(new Error(`failed with ${sampleToken}`));
  assert.equal(safeError.message, 'failed with [REDACTED]');
  assert.equal(safeError.stack, undefined);
});

test('run ID and viewport fixture naming are E2E-scoped and unique', () => {
  const base = createRunId(new Date('2026-07-18T01:02:03Z'), Buffer.from('abcd', 'hex'));
  assert.equal(base, 'E2E-20260718T010203-abcd');
  assert.equal(createViewportRunId(base, { width: 360 }), 'E2E-20260718T010203-abcd-360');
  assert.notEqual(createViewportRunId(base, { width: 360 }), createViewportRunId(base, { width: 390 }));
  const payload = buildBookingPayload(`${base}-360`, '+66000000001', new Date('2026-07-18T01:02:03Z'));
  assert.ok(payload.customer.name.startsWith(TEST_NAME_PREFIX));
  assert.ok(payload.additionalRequests.includes(E2E_MARKER));
  assert.ok(payload.specialRequests.includes(`${base}-360`));
});

test('fixture registry keeps partial records available for cleanup', () => {
  const registry = new FixtureRegistry();
  registry.add({
    runId: 'E2E-20260718T010203-abcd-360',
    viewport: '360x800',
    bookingNumber: null,
    customerName: '[E2E] Customer E2E-20260718T010203-abcd-360',
    marker: `${E2E_MARKER} E2E-20260718T010203-abcd-360`,
    adminToken: 'secret-token',
  });
  registry.update('E2E-20260718T010203-abcd-360', { bookingNumber: 'TX202607180001' });
  assert.equal(registry.pending().length, 1);
  assert.equal(registry.manifest()[0].adminToken, undefined);
  assert.equal(registry.manifest()[0].bookingNumber, 'TX202607180001');
});

test('fixture registry exposes explicit pending and mark APIs', () => {
  const registry = new FixtureRegistry();
  registry.add({
    runId: 'E2E-20260718T010203-abcd-360',
    bookingNumber: 'TX202607180001',
    customerName: '[E2E] Customer E2E-20260718T010203-abcd-360',
    marker: `${E2E_MARKER} E2E-20260718T010203-abcd-360`,
  });
  registry.add({
    runId: 'E2E-20260718T010203-abcd-390',
    bookingNumber: null,
    customerName: '[E2E] Customer E2E-20260718T010203-abcd-390',
    marker: `${E2E_MARKER} E2E-20260718T010203-abcd-390`,
  });
  assert.equal(registry.pendingCleanup().length, 1);
  registry.markCleanupFailed('E2E-20260718T010203-abcd-360', new Error('temporary'));
  assert.equal(registry.pendingCleanup().length, 1);
  registry.markArchived('E2E-20260718T010203-abcd-360');
  assert.equal(registry.pendingCleanup().length, 0);
  registry.markKept('E2E-20260718T010203-abcd-390');
  assert.equal(registry.pendingCleanup().length, 0);
  assert.equal(registry.get('E2E-20260718T010203-abcd-390').cleanupStatus, 'kept');
});

test('local cleanup candidate rejects non-E2E records', () => {
  assert.equal(assertCleanupCandidate(cleanupFixture()), true);
  assert.throws(() => assertCleanupCandidate(cleanupFixture({ runId: 'BAD' })), /run ID/);
  assert.throws(() => assertCleanupCandidate(cleanupFixture({ bookingNumber: null })), /booking number/);
  assert.throws(() => assertCleanupCandidate(cleanupFixture({ customerName: 'Real Customer' })), /non-E2E/);
  assert.throws(() => assertCleanupCandidate(cleanupFixture({ marker: 'missing marker' })), /E2E marker/);
});

test('server-side cleanup verification rejects mismatches before archive', () => {
  const fixture = cleanupFixture();
  assert.equal(assertServerCleanupCandidate(fixture, serverBooking(fixture)), true);
  assert.throws(
    () => assertServerCleanupCandidate(fixture, serverBooking(fixture, { specialRequests: `${E2E_MARKER} other-run` })),
    /server marker run ID/,
  );
  assert.throws(
    () => assertServerCleanupCandidate(fixture, serverBooking(fixture, { customer: { name: 'Real Customer' } })),
    /customer name/,
  );
  assert.throws(
    () => assertServerCleanupCandidate(fixture, serverBooking(fixture, { customer: { name: '[E2E] Customer other' } })),
    /customer run ID/,
  );
  assert.throws(
    () => assertServerCleanupCandidate(fixture, serverBooking(fixture, { bookingNumber: 'TX202607180999' })),
    /booking number/,
  );
});

test('network request classification and URL sanitization are stable', () => {
  assert.equal(
    classifyNetworkUrl('https://trider.taxi/api/v1/public/bookings/42/driver-location'),
    'guestLocation',
  );
  assert.equal(classifyNetworkUrl('https://trider.taxi/api/v1/public/bookings/lookup'), 'guestLookup');
  assert.equal(classifyNetworkUrl('https://trider.taxi/socket.io/?EIO=4'), 'socketTransport');
  assert.equal(sanitizeUrl('https://trider.taxi/path?guestAccessToken=secret#hash'), 'https://trider.taxi/path');
});

test('token-like query values are rejected while token fingerprints stay stable', () => {
  assert.throws(
    () => assertNoTokenInUrl('https://trider.taxi/booking/lookup?guestAccessToken=abcdefghijklmnopqrstuvwxyz123456'),
    /Secret-like query/,
  );
  assert.equal(tokenFingerprint('secret-token-value'), tokenFingerprint('secret-token-value'));
  assert.notEqual(tokenFingerprint('secret-token-value'), tokenFingerprint('another-secret-token-value'));
});

test('network audit detects guest lookup polling, interval drift, token rotation, and terminal leaks', () => {
  const audit = new NetworkAudit();
  const first = Date.now();
  audit.recordRequest('https://trider.taxi/api/v1/public/bookings/lookup', 'POST');
  audit.recordRequest('https://trider.taxi/api/v1/public/bookings/99/driver-location', 'GET', {
    'x-guest-access-token': 'token-one-123456789012345678901234567890',
  });
  audit.events[audit.events.length - 1].at = first;
  audit.recordRequest('https://trider.taxi/api/v1/public/bookings/99/driver-location', 'GET', {
    'x-guest-access-token': 'token-one-123456789012345678901234567890',
  });
  audit.events[audit.events.length - 1].at = first + 15000;
  audit.assertLocationPollingObserved(2);
  audit.assertGuestLocationInterval({ expectedMs: 15000, toleranceMs: 10 });
  audit.assertStableGuestTokenFingerprint();
  audit.assertNoRepeatedGuestLookup(1);
  audit.assertNoGuestLocationAfter(first + 15000, 10);

  audit.recordRequest('https://trider.taxi/api/v1/public/bookings/lookup', 'POST');
  assert.throws(() => audit.assertNoRepeatedGuestLookup(1), /Guest lookup endpoint/);

  const tokenAudit = new NetworkAudit();
  tokenAudit.recordRequest('https://trider.taxi/api/v1/public/bookings/99/driver-location', 'GET', {
    'x-guest-access-token': 'token-one-123456789012345678901234567890',
  });
  tokenAudit.recordRequest('https://trider.taxi/api/v1/public/bookings/99/driver-location', 'GET', {
    'x-guest-access-token': 'token-two-123456789012345678901234567890',
  });
  assert.throws(() => tokenAudit.assertStableGuestTokenFingerprint(), /multiple/);
});

test('websocket audit counts browser websocket connections, not Engine.IO HTTP requests', () => {
  const audit = new NetworkAudit();
  audit.recordRequest('https://trider.taxi/socket.io/?EIO=4', 'GET');
  audit.recordRequest('https://trider.taxi/socket.io/?EIO=4&transport=polling', 'POST');
  audit.assertWebSocketConnectionLimit(0);
  audit.recordWebSocket('wss://trider.taxi/socket.io/?EIO=4&transport=websocket');
  audit.assertWebSocketConnectionLimit(1);
  audit.recordWebSocket('wss://trider.taxi/socket.io/?EIO=4&transport=websocket');
  assert.equal(audit.socketReconnectCount(), 1);
  assert.throws(() => audit.assertWebSocketConnectionLimit(1), /WebSocket/);
});

function e2eConfig() {
  return {
    backendUrl: 'https://trider.taxi',
    customerPhone: '+66000000001',
    driverId: 12,
  };
}

function auth() {
  return {
    adminToken: 'admin-token-123456789012345678901234567890',
    driverToken: 'driver-token-123456789012345678901234567890',
  };
}

function jsonResponse(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json' },
  });
}

function mockFetch(responses) {
  const calls = [];
  const original = global.fetch;
  global.fetch = async (url, options = {}) => {
    calls.push({ url: String(url), options });
    const next = responses.shift();
    if (!next) throw new Error(`Unexpected fetch call: ${url}`);
    if (next.error) throw next.error;
    return jsonResponse(next.body, next.status ?? 200);
  };
  return {
    calls,
    restore() {
      global.fetch = original;
    },
  };
}

test('prepare failure before booking creation leaves no cleanup candidate', async () => {
  const registry = new FixtureRegistry();
  const fetchMock = mockFetch([{ body: { success: false, message: 'bad' }, status: 500 }]);
  await assert.rejects(
    () => prepareFixture(e2eConfig(), 'E2E-20260718T010203-abcd-360', auth(), registry, { width: 360, height: 800 }),
    FixturePreparationError,
  );
  fetchMock.restore();
  assert.equal(registry.get('E2E-20260718T010203-abcd-360').bookingNumber, null);
  assert.equal(registry.pendingCleanup().length, 0);
});

test('booking created plus lookup failure remains cleanable through final sweep', async () => {
  const registry = new FixtureRegistry();
  const runId = 'E2E-20260718T010203-abcd-360';
  const fetchMock = mockFetch([
    { body: { data: { bookingNumber: 'TX202607180001', id: 10 } } },
    { body: { success: false, message: 'lookup failed' }, status: 500 },
    {
      body: {
        data: serverBooking(cleanupFixture({
          runId,
          bookingNumber: 'TX202607180001',
        })),
      },
    },
    { body: { data: { archived: true } } },
  ]);
  await assert.rejects(
    () => prepareFixture(e2eConfig(), runId, auth(), registry, { width: 360, height: 800 }),
    FixturePreparationError,
  );
  assert.equal(registry.get(runId).bookingNumber, 'TX202607180001');
  await cleanupPendingFixtures(e2eConfig(), registry);
  fetchMock.restore();
  assert.equal(registry.get(runId).cleanupStatus, 'archived');
  assert.equal(fetchMock.calls.some((call) => call.url.includes('/archive')), true);
});

test('booking created plus assignment failure remains cleanable through final sweep', async () => {
  const registry = new FixtureRegistry();
  const runId = 'E2E-20260718T010203-abcd-390';
  const fixture = cleanupFixture({ runId, bookingNumber: 'TX202607180002' });
  const fetchMock = mockFetch([
    { body: { data: { bookingNumber: fixture.bookingNumber, id: 11 } } },
    { body: { data: { bookingNumber: fixture.bookingNumber, bookingId: 11, guestAccessToken: 'guest-token-123456789012345678901234567890' } } },
    { body: { success: false, message: 'assignment conflict' }, status: 409 },
    { body: { data: serverBooking(fixture) } },
    { body: { data: { archived: true } } },
  ]);
  await assert.rejects(
    () => prepareFixture(e2eConfig(), runId, auth(), registry, { width: 390, height: 844 }),
    FixturePreparationError,
  );
  await cleanupPendingFixtures(e2eConfig(), registry);
  fetchMock.restore();
  assert.equal(registry.get(runId).cleanupStatus, 'archived');
});

test('lookup response without bookingId or guest token still triggers cleanup path', async () => {
  const registry = new FixtureRegistry();
  const runId = 'E2E-20260718T010203-abcd-430';
  const fixture = cleanupFixture({ runId, bookingNumber: 'TX202607180003' });
  const fetchMock = mockFetch([
    { body: { data: { bookingNumber: fixture.bookingNumber, id: 12 } } },
    { body: { data: { bookingNumber: fixture.bookingNumber } } },
    { body: { data: serverBooking(fixture) } },
    { body: { data: { archived: true } } },
  ]);
  await assert.rejects(
    () => prepareFixture(e2eConfig(), runId, auth(), registry, { width: 430, height: 932 }),
    FixturePreparationError,
  );
  await cleanupPendingFixtures(e2eConfig(), registry);
  fetchMock.restore();
  assert.equal(registry.get(runId).cleanupStatus, 'archived');
});

test('cleanup failure marks registry failed and preserves aggregate cleanup error', async () => {
  const registry = new FixtureRegistry();
  const fixture = cleanupFixture();
  registry.add(fixture);
  const fetchMock = mockFetch([{ body: { success: false, message: 'detail failed' }, status: 500 }]);
  await assert.rejects(() => cleanupPendingFixtures(e2eConfig(), registry), /cleanup attempts failed/);
  fetchMock.restore();
  assert.equal(registry.get(fixture.runId).cleanupStatus, 'failed');
  assert.match(registry.get(fixture.runId).cleanupError, /failed HTTP 500/);
});
