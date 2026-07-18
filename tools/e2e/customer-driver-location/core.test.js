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
  extractGuestAccess,
  redact,
  redactString,
  sanitizeUrl,
  serializeSafeError,
  tokenFingerprint,
} = require('./core');
const {
  activateFlutterSemanticsPlaceholder,
  collectFlutterDiagnostics,
  cleanupPendingFixtures,
  enableFlutterSemantics,
  fillLookupForm,
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

function fakeLocator({
  count = 0,
  value = '',
  onClick = null,
  clickError = null,
  fillTransform = null,
} = {}) {
  const state = { value, clicks: 0, fills: [] };
  const locator = {
    state,
    async count() {
      return typeof count === 'function' ? count() : count;
    },
    first() {
      return {
        async click(options) {
          if (clickError) throw clickError;
          state.clicks += 1;
          if (onClick) onClick(options);
        },
        async waitFor() {
          if ((typeof count === 'function' ? count() : count) < 1) {
            throw new Error('not found');
          }
        },
      };
    },
    async fill(nextValue) {
      state.value = fillTransform ? fillTransform(nextValue) : nextValue;
      state.fills.push(nextValue);
    },
    async pressSequentially(nextValue) {
      state.value = fillTransform ? fillTransform(nextValue) : nextValue;
      state.fills.push(nextValue);
    },
    async inputValue() {
      return state.value;
    },
    async click(options) {
      if (clickError) throw clickError;
      state.clicks += 1;
      if (onClick) onClick(options);
    },
  };
  return locator;
}

function fakeFlutterPage({
  placeholderCount = 0,
  textboxCount = 2,
  inputCount = 0,
  buttonCount = 1,
  bookingCount = 1,
  phoneCount = 1,
  lookupButtonCount = 1,
  waitForFunctionFails = false,
  url = 'https://trider.taxi/booking/lookup?safeParam=not-sensitive#hash',
  placeholderClickError = null,
  phoneFillTransform = null,
} = {}) {
  let currentPlaceholderCount = placeholderCount;
  const placeholder = fakeLocator({
    count: () => currentPlaceholderCount,
    clickError: placeholderClickError,
    onClick: () => {
      currentPlaceholderCount = 0;
    },
  });
  const accessibilityButton = fakeLocator({ count: 0 });
  const booking = fakeLocator({ count: bookingCount });
  const phone = fakeLocator({ count: phoneCount, fillTransform: phoneFillTransform });
  const lookupButton = fakeLocator({ count: lookupButtonCount });
  return {
    placeholder,
    booking,
    phone,
    lookupButton,
    url: () => url,
    locator(selector) {
      if (selector === 'flt-semantics-placeholder') return placeholder;
      return fakeLocator({ count: 0 });
    },
    getByRole(role, options = {}) {
      if (role === 'button' && /enable accessibility/i.test(String(options.name))) {
        return accessibilityButton;
      }
      if (
        role === 'textbox' &&
        (options.name?.test?.('booking number') || options.name?.test?.('예약번호'))
      ) {
        return booking;
      }
      if (
        role === 'textbox' &&
        (options.name?.test?.('phone') || options.name?.test?.('전화번호'))
      ) {
        return phone;
      }
      if (
        role === 'button' &&
        (options.name?.test?.('Find booking') || options.name?.test?.('예약 조회'))
      ) {
        return lookupButton;
      }
      return fakeLocator({ count: 0 });
    },
    async waitForFunction() {
      if (waitForFunctionFails) throw new Error('timed out');
    },
    async evaluate(fn) {
      if (
        typeof fn === 'function' &&
        String(fn).includes('flt-semantics-placeholder') &&
        String(fn).includes('.click')
      ) {
        if (currentPlaceholderCount < 1) return false;
        currentPlaceholderCount = 0;
        return true;
      }
      return {
        flutterView: 1,
        glassPane: 1,
        semanticsPlaceholder: currentPlaceholderCount,
        applicationRole: 0,
        textboxRole: textboxCount,
        input: inputCount,
        textarea: 0,
        buttonRole: buttonCount,
      };
    },
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
    guestAccess: { token: sampleToken },
    nested: { Authorization: `Bearer ${sampleToken}` },
    response: { body: { token: sampleToken } },
    safe: 'hello',
  });
  assert.equal(redacted.guestAccessToken, '[REDACTED]');
  assert.equal(redacted.guestAccess.token, '[REDACTED]');
  assert.equal(redacted.nested.Authorization, '[REDACTED]');
  assert.equal(redacted.response.body.token, '[REDACTED]');
  assert.equal(redacted.safe, 'hello');
  assert.equal(redactString(`Bearer ${sampleToken}`), 'Bearer [REDACTED]');
  const safeError = serializeSafeError(new Error(`failed with ${sampleToken}`));
  assert.equal(safeError.message, 'failed with [REDACTED]');
  assert.equal(safeError.stack, undefined);
});

test('extractGuestAccess reads the nested guest lookup contract only', () => {
  const access = extractGuestAccess({
    guestAccess: {
      token: 'valid-test-token-value',
      expiresAt: '2026-07-19T00:00:00Z',
    },
  });
  assert.deepEqual(access, {
    token: 'valid-test-token-value',
    expiresAt: '2026-07-19T00:00:00Z',
  });
  assert.deepEqual(extractGuestAccess({
    guestAccess: { token: 'valid-test-token-value' },
  }), {
    token: 'valid-test-token-value',
    expiresAt: null,
  });
});

test('extractGuestAccess rejects missing nested token without leaking values', () => {
  for (const value of [
    {},
    { guestAccess: null },
    { guestAccess: {} },
    { guestAccess: { token: '' } },
    { guestAccess: { token: '   ' } },
    { guestAccessToken: 'legacy-token-that-must-not-be-accepted' },
  ]) {
    assert.throws(
      () => extractGuestAccess(value),
      (err) => {
        assert.equal(err.message, 'Guest lookup response did not contain guestAccess.token');
        assert.equal(err.message.includes('legacy-token-that-must-not-be-accepted'), false);
        return true;
      },
    );
  }
});

test('collectFlutterDiagnostics stores only safe path and selector counts', async () => {
  const diagnostics = await collectFlutterDiagnostics(fakeFlutterPage());
  assert.equal(diagnostics.pathname, '/booking/lookup');
  assert.equal(diagnostics.textboxRole, 2);
  assert.equal(JSON.stringify(diagnostics).includes('guestAccessToken'), false);
  assert.equal(JSON.stringify(diagnostics).includes('not-sensitive'), false);
});

test('enableFlutterSemantics clicks the Flutter placeholder once and is safe to call repeatedly', async () => {
  const page = fakeFlutterPage({ placeholderCount: 1, textboxCount: 2 });
  await enableFlutterSemantics(page);
  await enableFlutterSemantics(page);
  assert.equal(page.placeholder.state.clicks, 1);
});

test('activateFlutterSemanticsPlaceholder falls back to DOM activation when Playwright click cannot scroll it into view', async () => {
  const page = fakeFlutterPage({
    placeholderCount: 1,
    textboxCount: 2,
    placeholderClickError: new Error('Element is outside of the viewport'),
  });
  const clicked = await activateFlutterSemanticsPlaceholder(page);
  assert.equal(clicked, true);
  assert.equal(page.placeholder.state.clicks, 0);
  const diagnostics = await collectFlutterDiagnostics(page);
  assert.equal(diagnostics.semanticsPlaceholder, 0);
});

test('enableFlutterSemantics succeeds without clicking when textboxes already exist', async () => {
  const page = fakeFlutterPage({ placeholderCount: 0, textboxCount: 2 });
  const diagnostics = await enableFlutterSemantics(page);
  assert.equal(page.placeholder.state.clicks, 0);
  assert.equal(diagnostics.textboxRole, 2);
});

test('enableFlutterSemantics fails clearly when no accessible editable fields appear', async () => {
  const page = fakeFlutterPage({ placeholderCount: 0, textboxCount: 0, inputCount: 0 });
  await assert.rejects(
    () => enableFlutterSemantics(page),
    (err) => {
      assert.match(err.message, /exposed no editable fields/);
      assert.equal(err.message.includes('guestAccessToken'), false);
      return true;
    },
  );
});

test('fillLookupForm uses unique semantic labels and does not rely on nth textbox fallback', async () => {
  const page = fakeFlutterPage();
  await fillLookupForm(page, {
    bookingNumber: 'TX202607180999',
    customerPhone: '+66000000001',
  });
  assert.deepEqual(page.booking.state.fills, ['TX202607180999']);
  assert.deepEqual(page.phone.state.fills, ['+66000000001']);
});

test('fillLookupForm accepts localized semantic labels used by staging Flutter Web', async () => {
  const page = fakeFlutterPage();
  await fillLookupForm(page, {
    bookingNumber: 'TX202607180998',
    customerPhone: '+66000000002',
  });
  assert.deepEqual(page.booking.state.fills, ['TX202607180998']);
  assert.deepEqual(page.phone.state.fills, ['+66000000002']);
});

test('fillLookupForm accepts phone input formatting differences without leaking the phone value', async () => {
  const page = fakeFlutterPage({
    phoneFillTransform: (value) => value.replace(/[^\d]/g, ''),
  });
  await fillLookupForm(page, {
    bookingNumber: 'TX202607180997',
    customerPhone: '+66000000003',
  });
  assert.deepEqual(page.phone.state.fills, ['+66000000003']);
});

test('fillLookupForm rejects missing or ambiguous semantic fields', async () => {
  await assert.rejects(
    () => fillLookupForm(fakeFlutterPage({ bookingCount: 0 }), {
      bookingNumber: 'TX202607180999',
      customerPhone: '+66000000001',
    }),
    /booking number locator was not found/,
  );
  await assert.rejects(
    () => fillLookupForm(fakeFlutterPage({ bookingCount: 2 }), {
      bookingNumber: 'TX202607180999',
      customerPhone: '+66000000001',
    }),
    /booking number locator matched 2 elements/,
  );
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
    {
      body: {
        data: {
          bookingNumber: fixture.bookingNumber,
          bookingId: 11,
          guestAccess: {
            token: 'guest-token-123456789012345678901234567890',
            expiresAt: '2026-07-19T00:00:00Z',
          },
        },
      },
    },
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

test('prepare fixture stores nested guest access at runtime without exposing it in manifest', async () => {
  const registry = new FixtureRegistry();
  const runId = 'E2E-20260718T010203-abcd-410';
  const fixture = cleanupFixture({ runId, bookingNumber: 'TX202607180004' });
  const token = 'guest-token-123456789012345678901234567891';
  const fetchMock = mockFetch([
    { body: { data: { bookingNumber: fixture.bookingNumber, id: 13 } } },
    {
      body: {
        data: {
          bookingNumber: fixture.bookingNumber,
          bookingId: 13,
          guestAccess: {
            token,
            expiresAt: '2026-07-19T00:00:00Z',
          },
        },
      },
    },
    { body: { data: { assigned: true } } },
  ]);
  const prepared = await prepareFixture(
    e2eConfig(),
    runId,
    auth(),
    registry,
    { width: 410, height: 900 },
  );
  fetchMock.restore();
  assert.equal(prepared.guestAccessToken, token);
  assert.equal(prepared.guestAccessExpiresAt, '2026-07-19T00:00:00Z');
  const manifest = registry.manifest();
  assert.equal(JSON.stringify(manifest).includes(token), false);
  assert.equal(manifest[0].guestAccessToken, undefined);
  assert.equal(manifest[0].guestAccessExpiresAt, undefined);
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
