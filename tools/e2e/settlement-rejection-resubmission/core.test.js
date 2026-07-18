const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');

const {
  MANIFEST_NAME,
  REJECTION_REASON,
  createSyntheticReceiptPng,
  parseArgs,
  writeManifest,
} = require('./run');

test('parseArgs defaults to live mode without keeping fixture', () => {
  assert.deepEqual(parseArgs([]), {
    dryRun: false,
    keepFixture: false,
  });
});

test('parseArgs supports dry-run and keep-fixture', () => {
  assert.deepEqual(parseArgs(['--dry-run', '--keep-fixture']), {
    dryRun: true,
    keepFixture: true,
  });
});

test('synthetic receipts include version marker and no real payment language', () => {
  const v1 = createSyntheticReceiptPng('E2E-SETTLEMENT-TEST', 'V1').toString('latin1');
  const v2 = createSyntheticReceiptPng('E2E-SETTLEMENT-TEST', 'V2').toString('latin1');
  assert.match(v1, /E2E TEST RECEIPT V1/);
  assert.match(v2, /E2E TEST RECEIPT V2/);
  assert.match(v1, /NOT A REAL PAYMENT/);
  assert.match(v2, /NOT A REAL PAYMENT/);
});

test('rejection reason is synthetic and non-sensitive', () => {
  assert.match(REJECTION_REASON, /E2E synthetic/);
  assert.doesNotMatch(REJECTION_REASON, /bank|account|phone|password|token/i);
});

test('writeManifest keeps only redacted rejection lifecycle metadata', () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'tride-rejection-resubmission-test-'));
  try {
    const registry = {
      records: [
        {
          runId: 'run-safe',
          bookingNumber: 'TX202607180299',
          v1ReceiptStatus: 'RECEIPT_SUBMITTED',
          v2ReceiptStatus: 'RECEIPT_SUBMITTED',
          settlementStatus: 'APPROVED',
          receiptStatus: 'APPROVED',
          rejectionReasonVerified: true,
          oldReceiptInactive: true,
          canApproveAfterResubmission: true,
          approvalCandidateVerified: true,
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
    assert.match(text, /TX202607180299/);
    assert.match(text, /oldReceiptInactive/);
    assert.doesNotMatch(text, /should-not-appear/);
    assert.doesNotMatch(text, /\+66000000000/);
    assert.doesNotMatch(text, /receipt\.png/);
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});
