const test = require('node:test');
const assert = require('node:assert/strict');
const {
  E2E_MARKER,
  NetworkAudit,
  TEST_NAME_PREFIX,
  assertCleanupCandidate,
  assertNoTokenInUrl,
  assertUrlAllowed,
  buildBookingPayload,
  buildConfig,
  classifyNetworkUrl,
  createRunId,
  redact,
  redactString,
  sanitizeUrl,
} = require('./core');

const stagingEnv = {
  TRIDE_E2E_TARGET: 'staging',
  TRIDE_E2E_FRONTEND_URL: 'https://trider.taxi',
  TRIDE_E2E_BACKEND_URL: 'https://trider.taxi',
};

test('production and unknown URLs are blocked', () => {
  assert.throws(
    () => assertUrlAllowed('url', 'https://88taxi.net', stagingEnv),
    /blocked host/,
  );
  assert.throws(
    () => assertUrlAllowed('url', 'https://example.com', stagingEnv),
    /not whitelisted/,
  );
});

test('staging whitelist accepts configured staging and localhost hosts', () => {
  assert.equal(assertUrlAllowed('url', 'https://trider.taxi/', stagingEnv), 'https://trider.taxi');
  assert.equal(assertUrlAllowed('url', 'http://127.0.0.1:3101', stagingEnv), 'http://127.0.0.1:3101');
});

test('config requires staging target and live secrets only for live mode', () => {
  const dry = buildConfig(stagingEnv);
  assert.equal(dry.frontendUrl, 'https://trider.taxi');
  assert.throws(() => buildConfig({ ...stagingEnv, TRIDE_E2E_TARGET: 'production' }), /TARGET=staging/);
  assert.throws(() => buildConfig(stagingEnv, { requireSecrets: true }), /Missing live E2E variables/);
  assert.throws(
    () => buildConfig({
      ...stagingEnv,
      TRIDE_E2E_ADMIN_EMAIL: 'tride.e2e.admin@example.com',
      TRIDE_E2E_ADMIN_PASSWORD: 'local-only',
      TRIDE_E2E_DRIVER_EMAIL: 'tride.e2e.driver@example.com',
      TRIDE_E2E_DRIVER_PASSWORD: 'local-only',
      TRIDE_E2E_DRIVER_ID: 'abc',
      TRIDE_E2E_CUSTOMER_PHONE: '+66000000001',
      TRIDE_E2E_ALLOW_LIVE: '1',
    }, { requireSecrets: true }),
    /DRIVER_ID/,
  );
});

test('token redaction removes secrets recursively', () => {
  const sampleToken = 'abc123456789012345678901234567890xyz';
  const redacted = redact({
    guestAccessToken: sampleToken,
    nested: { Authorization: `Bearer ${sampleToken}` },
    safe: 'hello',
  });
  assert.equal(redacted.guestAccessToken, '[REDACTED]');
  assert.equal(redacted.nested.Authorization, '[REDACTED]');
  assert.equal(redacted.safe, 'hello');
  assert.equal(redactString(`Bearer ${sampleToken}`), 'Bearer [REDACTED]');
});

test('run ID and fixture naming are E2E-scoped', () => {
  const runId = createRunId(new Date('2026-07-18T01:02:03Z'), Buffer.from('abcd', 'hex'));
  assert.equal(runId, 'E2E-20260718T010203-abcd');
  const payload = buildBookingPayload(runId, '+66000000001', new Date('2026-07-18T01:02:03Z'));
  assert.ok(payload.customer.name.startsWith(TEST_NAME_PREFIX));
  assert.ok(payload.additionalRequests.includes(E2E_MARKER));
  assert.ok(payload.specialRequests.includes(runId));
});

test('cleanup is limited to E2E marked synthetic bookings', () => {
  assert.equal(
    assertCleanupCandidate({
      runId: 'E2E-20260718T010203-abcd',
      customerName: '[E2E] Customer E2E-20260718T010203-abcd',
      marker: `${E2E_MARKER} E2E-20260718T010203-abcd`,
    }),
    true,
  );
  assert.throws(() => assertCleanupCandidate({ runId: 'BAD', customerName: '[E2E] A', marker: E2E_MARKER }), /run ID/);
  assert.throws(() => assertCleanupCandidate({ runId: 'E2E-1', customerName: 'Real Customer', marker: E2E_MARKER }), /non-E2E/);
});

test('network request classification and URL sanitization are stable', () => {
  assert.equal(
    classifyNetworkUrl('https://trider.taxi/api/v1/public/bookings/42/driver-location'),
    'guestLocation',
  );
  assert.equal(classifyNetworkUrl('https://trider.taxi/api/v1/public/bookings/lookup'), 'guestLookup');
  assert.equal(classifyNetworkUrl('https://trider.taxi/socket.io/?EIO=4'), 'socket');
  assert.equal(sanitizeUrl('https://trider.taxi/path?guestAccessToken=secret#hash'), 'https://trider.taxi/path');
});

test('token-like query values are rejected', () => {
  assert.throws(
    () => assertNoTokenInUrl('https://trider.taxi/booking/lookup?guestAccessToken=abcdefghijklmnopqrstuvwxyz123456'),
    /Secret-like query/,
  );
});

test('network audit detects guest lookup polling and duplicate socket reconnects', () => {
  const audit = new NetworkAudit();
  audit.recordRequest('https://trider.taxi/api/v1/public/bookings/lookup', 'POST');
  audit.recordRequest('https://trider.taxi/api/v1/public/bookings/99/driver-location', 'GET');
  audit.assertLocationPollingObserved();
  audit.assertNoRepeatedGuestLookup(1);
  audit.recordRequest('https://trider.taxi/api/v1/public/bookings/lookup', 'POST');
  assert.throws(() => audit.assertNoRepeatedGuestLookup(1), /Guest lookup endpoint/);

  const socketAudit = new NetworkAudit();
  socketAudit.recordRequest('https://trider.taxi/socket.io/?EIO=4', 'GET');
  socketAudit.recordRequest('https://trider.taxi/socket.io/?EIO=4', 'GET');
  assert.throws(() => socketAudit.assertSocketSubscribeLimit(1), /Socket/);
});
