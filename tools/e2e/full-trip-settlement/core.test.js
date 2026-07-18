const test = require('node:test');
const assert = require('node:assert/strict');
const {
  E2E_MARKER,
  FixtureRegistry,
  buildConfig,
  redact,
} = require('../customer-driver-location/core');
const {
  CUSTOMER_VIEWPORT,
  assertDriverReleased,
  assertFinalCustomerState,
  assertFullTripApprovalCandidate,
  parseArgs,
  writeManifest,
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

function fixture(overrides = {}) {
  const runId = overrides.runId || 'E2E-20260718T010203-abcd-390';
  return {
    runId,
    bookingNumber: 'TX202607180001',
    customerName: `[E2E] Customer ${runId}`,
    marker: `${E2E_MARKER} ${runId}`,
    ...overrides,
  };
}

function serverBooking(record, overrides = {}) {
  return {
    bookingNumber: record.bookingNumber,
    customer: { name: record.customerName },
    specialRequests: record.marker,
    status: 'SETTLEMENT_PENDING',
    assignedDriver: { id: 12 },
    ...overrides,
  };
}

function adminSettlement(overrides = {}) {
  return {
    commissionStatus: 'RECEIPT_SUBMITTED',
    receiptStatus: 'RECEIPT_SUBMITTED',
    canApprove: true,
    receiptMetadata: { originalFilename: 'full-trip-e2e.png', mimeType: 'image/png' },
    ...overrides,
  };
}

test('full trip dry-run config is staging-only and reuses customer viewport', () => {
  const config = buildConfig(stagingEnv, { requireSecrets: false });
  assert.equal(config.frontendHost, 'trider.taxi');
  assert.deepEqual(CUSTOMER_VIEWPORT, { width: 390, height: 844 });
});

test('full trip live config requires explicit E2E staging credentials', () => {
  assert.throws(() => buildConfig(stagingEnv, { requireSecrets: true }), /Missing live E2E/);
  const config = buildConfig(liveEnv(), { requireSecrets: true });
  assert.equal(config.driverId, 12);
  assert.throws(
    () => buildConfig(liveEnv({ TRIDE_E2E_ALLOW_LIVE: '0' }), { requireSecrets: true }),
    /ALLOW_LIVE/,
  );
});

test('full trip parser supports dry-run, headed, keep-fixture, and browser project', () => {
  assert.deepEqual(parseArgs([]), {
    dryRun: false,
    headed: false,
    keepFixture: false,
    project: 'chromium',
  });
  assert.deepEqual(parseArgs(['--dry-run', '--headed', '--keep-fixture', '--project=firefox']), {
    dryRun: true,
    headed: true,
    keepFixture: true,
    project: 'firefox',
  });
});

test('full trip assertions require completed customer state and released driver', () => {
  assert.equal(assertFinalCustomerState({ status: 'COMPLETED' }), undefined);
  assert.throws(() => assertFinalCustomerState({ status: 'SETTLEMENT_PENDING' }), /COMPLETED/);
  assert.equal(assertDriverReleased({ hasActiveJob: false }), undefined);
  assert.equal(assertDriverReleased({}), undefined);
  assert.throws(() => assertDriverReleased({ hasActiveJob: true }), /active job/);
});

test('full trip approval candidate accepts customer location fixture marker', () => {
  const record = fixture();
  assert.equal(
    assertFullTripApprovalCandidate(record, serverBooking(record), adminSettlement(), 12),
    true,
  );
});

test('full trip approval candidate rejects unsafe or not-ready bookings', () => {
  const record = fixture();
  assert.throws(
    () => assertFullTripApprovalCandidate(
      record,
      serverBooking(record, { specialRequests: 'OTHER' }),
      adminSettlement(),
      12,
    ),
    /marker/,
  );
  assert.throws(
    () => assertFullTripApprovalCandidate(
      record,
      serverBooking(record, { status: 'PICKED_UP' }),
      adminSettlement(),
      12,
    ),
    /SETTLEMENT_PENDING/,
  );
  assert.throws(
    () => assertFullTripApprovalCandidate(
      record,
      serverBooking(record),
      adminSettlement({ canApprove: false }),
      12,
    ),
    /canApprove/,
  );
});

test('full trip manifest is redacted and keeps cleanup state only', () => {
  const registry = new FixtureRegistry();
  registry.add({
    runId: 'E2E-SETTLEMENT-20260718T010203-abcd',
    bookingNumber: 'TX202607180001',
    marker: `${E2E_MARKER} E2E-SETTLEMENT-20260718T010203-abcd`,
    driverToken: 'secret-token-value-secret-token-value',
    guestAccessToken: 'guest-token-value-guest-token-value',
  });
  registry.markArchived('E2E-SETTLEMENT-20260718T010203-abcd');
  const tmp = require('node:fs').mkdtempSync(
    require('node:path').join(require('node:os').tmpdir(), 'tride-full-trip-test-'),
  );
  try {
    const manifest = writeManifest({ artifactDir: tmp }, registry);
    const text = require('node:fs').readFileSync(manifest, 'utf8');
    assert.equal(text.includes('secret-token-value'), false);
    assert.equal(text.includes('guest-token-value'), false);
    assert.equal(text.includes('"cleanupStatus": "archived"'), true);
    assert.equal(redact({ accessToken: 'secret-token-value-secret-token-value' }).accessToken, '[REDACTED]');
  } finally {
    require('node:fs').rmSync(tmp, { recursive: true, force: true });
  }
});
