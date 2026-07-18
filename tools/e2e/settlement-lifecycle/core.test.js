const test = require('node:test');
const assert = require('node:assert/strict');
const {
  E2E_MARKER,
  FixtureRegistry,
  assertUrlAllowed,
  buildConfig,
  createRunId,
  redact,
} = require('./core');
const {
  EXPECTED_COMMISSION_AMOUNT,
  EXPECTED_CURRENCY,
  assertMoneyFields,
  assertSettlementCleanupCandidate,
  buildRunFailure,
  createSyntheticReceiptPng,
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

function cleanupFixture(overrides = {}) {
  const runId = overrides.runId || 'E2E-SETTLEMENT-20260718T010203-abcd';
  return {
    runId,
    bookingNumber: 'TX202607180001',
    customerName: `[E2E] Settlement Customer ${runId}`,
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

test('settlement E2E run ID and marker are scoped to settlement lifecycle', () => {
  const runId = createRunId(new Date('2026-07-18T01:02:03Z'), Buffer.from([0xab, 0xcd]));
  assert.equal(runId, 'E2E-SETTLEMENT-20260718T010203-abcd');
  assert.equal(E2E_MARKER, 'SETTLEMENT_LIFECYCLE_E2E');
});

test('staging host guard blocks production and unknown hosts', () => {
  assert.equal(assertUrlAllowed('url', 'https://trider.taxi'), 'https://trider.taxi');
  assert.throws(() => assertUrlAllowed('url', 'https://88taxi.net'), /blocked host/);
  assert.throws(() => assertUrlAllowed('url', 'https://example.com'), /not hard-allowed/);
  assert.throws(() => assertUrlAllowed('url', 'http://trider.taxi'), /HTTPS/);
});

test('live config requires explicit staging opt-in and secrets only for live mode', () => {
  const dry = buildConfig(stagingEnv, { requireSecrets: false });
  assert.equal(dry.frontendHost, 'trider.taxi');
  assert.throws(() => buildConfig(stagingEnv, { requireSecrets: true }), /Missing live E2E/);
  const live = buildConfig(liveEnv(), { requireSecrets: true });
  assert.equal(live.driverId, 12);
  assert.throws(
    () => buildConfig(liveEnv({ TRIDE_E2E_ALLOW_LIVE: '0' }), { requireSecrets: true }),
    /ALLOW_LIVE/,
  );
});

test('redaction removes nested credentials from errors and objects', () => {
  const safe = redact({
    accessToken: 'secret-token-value-secret-token-value',
    nested: { password: 'pw' },
    message: 'Bearer abcdefghijklmnopqrstuvwxyzabcdef',
  });
  assert.equal(safe.accessToken, '[REDACTED]');
  assert.equal(safe.nested.password, '[REDACTED]');
  assert.equal(safe.message.includes('Bearer [REDACTED]'), true);
});

test('synthetic receipt is a PNG and embeds only E2E text', () => {
  const runId = 'E2E-SETTLEMENT-20260718T010203-abcd';
  const png = createSyntheticReceiptPng(runId);
  assert.deepEqual([...png.subarray(0, 8)], [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  const text = png.toString('latin1');
  assert.equal(text.includes('E2E TEST RECEIPT'), true);
  assert.equal(text.includes('NOT A REAL PAYMENT'), true);
  assert.equal(text.includes(runId), true);
  assert.equal(text.includes('bank'), false);
});

test('money fields follow backend settlement contract', () => {
  const result = assertMoneyFields({
    customerTotalAmount: 1300,
    companyCommissionAmount: EXPECTED_COMMISSION_AMOUNT,
    driverExpectedIncomeAmount: 1100,
    currency: EXPECTED_CURRENCY,
    customerTotalCurrency: EXPECTED_CURRENCY,
    companyCommissionCurrency: EXPECTED_CURRENCY,
    driverExpectedIncomeCurrency: EXPECTED_CURRENCY,
  });
  assert.deepEqual(result, { customerTotal: 1300, commission: 200, expectedIncome: 1100 });
  assert.throws(() => assertMoneyFields({ customerTotalAmount: 1300 }), /commission/);
  assert.throws(
    () => assertMoneyFields({
      customerTotalAmount: 1300,
      companyCommissionAmount: 200,
      driverExpectedIncomeAmount: -1,
      currency: 'THB',
      customerTotalCurrency: 'THB',
      companyCommissionCurrency: 'THB',
      driverExpectedIncomeCurrency: 'THB',
    }),
    /expected income/,
  );
});

test('cleanup candidate requires matching booking, customer, marker, and run ID', () => {
  const fixture = cleanupFixture();
  assert.equal(assertSettlementCleanupCandidate(fixture, serverBooking(fixture)), true);
  assert.throws(
    () => assertSettlementCleanupCandidate(fixture, serverBooking(fixture, { specialRequests: 'OTHER' })),
    /marker/,
  );
  assert.throws(
    () => assertSettlementCleanupCandidate(fixture, serverBooking(fixture, { customer: { name: '[E2E] Other' } })),
    /customer/,
  );
});

test('manifest allowlist excludes credentials and payment artifacts', () => {
  const registry = new FixtureRegistry();
  registry.add({
    ...cleanupFixture(),
    adminToken: 'placeholder',
    driverToken: 'placeholder',
    customerPhone: '+66000000001',
    receiptBytes: Buffer.from('secret'),
    settlementStatus: 'APPROVED',
    receiptStatus: 'RECEIPT_SUBMITTED',
    approvalStatus: 'approved',
    bookingFinalStatus: 'COMPLETED',
  });
  const tempDir = require('node:fs').mkdtempSync(require('node:path').join(require('node:os').tmpdir(), 'tride-manifest-'));
  try {
    const manifestPath = writeManifest({ artifactDir: tempDir }, registry);
    const manifest = JSON.parse(require('node:fs').readFileSync(manifestPath, 'utf8'));
    assert.deepEqual(Object.keys(manifest[0]).sort(), [
      'approvalStatus',
      'bookingFinalStatus',
      'bookingNumber',
      'cleanupStatus',
      'preparationStatus',
      'receiptStatus',
      'runId',
      'settlementStatus',
    ].sort());
    assert.equal(JSON.stringify(manifest).includes('placeholder'), false);
    assert.equal(JSON.stringify(manifest).includes('+66000000001'), false);
  } finally {
    require('node:fs').rmSync(tempDir, { recursive: true, force: true });
  }
});

test('run failure preserves primary and cleanup errors safely', () => {
  const primary = new Error('primary failed with Bearer abcdefghijklmnopqrstuvwxyzabcdef');
  const cleanup = new Error('cleanup failed');
  cleanup.failures = [{ bookingNumber: 'TX1', error: 'archive failed' }];
  const error = buildRunFailure(primary, cleanup);
  assert.equal(error.name, 'SettlementE2ERunFailure');
  assert.equal(error.primaryError.message.includes('Bearer [REDACTED]'), true);
  assert.equal(error.cleanupErrors.length, 1);
});

test('parse args supports dry-run and keep-fixture only', () => {
  assert.deepEqual(parseArgs(['--dry-run', '--keep-fixture']), {
    dryRun: true,
    keepFixture: true,
  });
});
