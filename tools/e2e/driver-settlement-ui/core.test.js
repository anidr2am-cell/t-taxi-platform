const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');

const {
  MANIFEST_NAME,
  VIEWPORT,
  driverSettlementE2EDetailUrl,
  formatAmount,
  parseArgs,
  seedDriverSession,
  writeManifest,
} = require('./run');

test('parseArgs defaults to headless chromium', () => {
  assert.deepEqual(parseArgs([]), {
    dryRun: false,
    headed: false,
    keepFixture: false,
    project: 'chromium',
  });
});

test('parseArgs supports dry-run, headed, keep-fixture, and project', () => {
  assert.deepEqual(parseArgs(['--dry-run', '--headed', '--keep-fixture', '--project=firefox']), {
    dryRun: true,
    headed: true,
    keepFixture: true,
    project: 'firefox',
  });
});

test('viewport remains mobile-first for driver web UI', () => {
  assert.equal(VIEWPORT.width, 390);
  assert.equal(VIEWPORT.height, 844);
});

test('formatAmount matches the driver THB display expectations', () => {
  assert.equal(formatAmount(120), '120');
  assert.equal(formatAmount(1080), '1,080');
  assert.equal(formatAmount(1200.5), '1,200.5');
});

test('driver settlement detail E2E URL requires a valid booking number', () => {
  const config = { frontendUrl: 'https://trider.taxi' };
  assert.equal(
    driverSettlementE2EDetailUrl(config, 'TX202607180001'),
    'https://trider.taxi/driver/e2e/settlement-detail?bookingNumber=TX202607180001',
  );
  assert.throws(
    () => driverSettlementE2EDetailUrl(config, ''),
    /valid booking number/,
  );
  assert.throws(
    () => driverSettlementE2EDetailUrl(config, '../admin'),
    /valid booking number/,
  );
});

test('seedDriverSession injects only driver auth storage keys', async () => {
  const calls = [];
  const context = {
    async addInitScript(script, token) {
      calls.push({ script: script.toString(), token });
    },
  };

  await seedDriverSession(context, 'driver-token');

  assert.equal(calls.length, 1);
  assert.equal(calls[0].token, 'driver-token');
  assert.match(calls[0].script, /flutter\.driver_access_token/);
  assert.match(calls[0].script, /driver_access_token/);
  assert.doesNotMatch(calls[0].script, /admin_access_token/);
});

test('seedDriverSession rejects a missing driver token', async () => {
  await assert.rejects(
    () => seedDriverSession({ addInitScript: async () => {} }, ''),
    /driver token/,
  );
});

test('writeManifest keeps only redacted safe run metadata', () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'tride-driver-settlement-ui-test-'));
  try {
    const registry = {
      records: [
        {
          runId: 'run-safe',
          bookingNumber: 'TX202607180099',
          uiUploadStatus: 'submitted',
          uiFileChooserMethod: 'semantic-filechooser',
          uiFileChooserClicks: 1,
          uiUploadClickMethod: 'semantic-button',
          uiUploadClicks: 1,
          settlementStatus: 'APPROVED',
          receiptStatus: 'APPROVED',
          approvalCandidateVerified: true,
          bookingFinalStatus: 'COMPLETED',
          preparationStatus: 'ready',
          cleanupStatus: 'archived',
          cleanupError: undefined,
          adminToken: 'should-not-appear',
          driverToken: 'should-not-appear',
          customerPhone: '+66000000000',
          receiptPath: '/tmp/receipt.png',
        },
      ],
    };
    const manifest = writeManifest({ artifactDir: tmp }, registry);
    assert.equal(path.basename(manifest), MANIFEST_NAME);
    const text = fs.readFileSync(manifest, 'utf8');
    assert.match(text, /TX202607180099/);
    assert.match(text, /semantic-filechooser/);
    assert.match(text, /semantic-button/);
    assert.doesNotMatch(text, /should-not-appear/);
    assert.doesNotMatch(text, /\+66000000000/);
    assert.doesNotMatch(text, /receipt\.png/);
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});
