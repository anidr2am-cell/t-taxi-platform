const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');

const {
  MANIFEST_NAME,
  VIEWPORT,
  parseArgs,
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

test('viewport remains desktop-sized for admin approval review', () => {
  assert.equal(VIEWPORT.width, 960);
  assert.equal(VIEWPORT.height, 800);
});

test('writeManifest keeps only redacted admin UI run metadata', () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'tride-admin-settlement-ui-test-'));
  try {
    const registry = {
      records: [
        {
          runId: 'run-safe',
          bookingNumber: 'TX202607180199',
          receiptUploadStatus: 'submitted',
          approvalCandidateVerified: true,
          adminCommissionStatusBeforeUi: 'RECEIPT_SUBMITTED',
          adminReceiptStatusBeforeUi: 'RECEIPT_SUBMITTED',
          adminCanApproveBeforeUi: true,
          uiApprovalStatus: 'approved',
          settlementStatus: 'APPROVED',
          receiptStatus: 'APPROVED',
          bookingFinalStatus: 'COMPLETED',
          driverActiveJobAfterApproval: false,
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
    assert.match(text, /TX202607180199/);
    assert.match(text, /approvalCandidateVerified/);
    assert.doesNotMatch(text, /should-not-appear/);
    assert.doesNotMatch(text, /\+66000000000/);
    assert.doesNotMatch(text, /receipt\.png/);
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});
