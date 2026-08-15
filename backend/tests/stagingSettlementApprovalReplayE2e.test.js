const test = require('node:test');
const assert = require('node:assert/strict');

const runner = require('../scripts/staging-booking-regression');
const cleanup = require('../scripts/e2eRegressionCleanup');
const replay = require('../scripts/staging-settlement-approval-replay-e2e');

const REGRESSION_MARKER = runner.REGRESSION_MARKER;

function settlementDetail(overrides = {}) {
  return {
    status: 'COMPLETED',
    commissionStatus: 'APPROVED',
    approvalMode: overrides.approvalMode ?? 'RECEIPT_VERIFIED',
    approval: { mode: overrides.approvalMode ?? 'RECEIPT_VERIFIED' },
    reviewHistory: overrides.reviewHistory ?? [{
      action: 'APPROVED',
      approvalMode: overrides.approvalMode ?? 'RECEIPT_VERIFIED',
    }],
    canManualApprove: overrides.canManualApprove ?? false,
    receiptFileId: overrides.receiptFileId ?? 249,
    commissionAmount: overrides.commissionAmount ?? 120,
  };
}

test('approval replay payloads use accepted regression cleanup marker', () => {
  assert.equal(replay.receiptBookingPayload().additionalRequests, REGRESSION_MARKER);
  assert.equal(replay.manualBookingPayload().additionalRequests, REGRESSION_MARKER);
  assert.match(replay.receiptBookingPayload().customer.name, /^\[E2E\]/);
  assert.match(replay.manualBookingPayload().customer.name, /^\[E2E\]/);
});

test('assertSafeE2ePayload rejects non-E2E customer name', () => {
  assert.throws(
    () => replay.assertSafeE2ePayload({
      customer: { name: 'Real Customer' },
      additionalRequests: REGRESSION_MARKER,
    }),
    /must start with \[E2E\]/,
  );
});

test('assertSafeE2ePayload rejects missing regression marker', () => {
  assert.throws(
    () => replay.assertSafeE2ePayload({
      customer: { name: '[E2E] Settlement Approval Replay Receipt' },
      additionalRequests: 'OTHER_MARKER',
    }),
    /AUTOMATED_REGRESSION_TEST/,
  );
});

test('assertReceiptApproveReplay accepts matching 200 replay state', () => {
  const detail = settlementDetail({ approvalMode: 'RECEIPT_VERIFIED' });
  assert.doesNotThrow(() => replay.assertReceiptApproveReplay(200, 200, detail, detail));
});

test('assertReceiptApproveReplay rejects non-200 retry', () => {
  const detail = settlementDetail({ approvalMode: 'RECEIPT_VERIFIED' });
  assert.throws(
    () => replay.assertReceiptApproveReplay(200, 409, detail, detail),
    /200\/200/,
  );
});

test('assertManualApproveReplay accepts matching manual replay state', () => {
  const detail = settlementDetail({
    approvalMode: 'MANUAL_WITHOUT_RECEIPT',
    reviewHistory: [{
      action: 'APPROVED',
      approvalMode: 'MANUAL_WITHOUT_RECEIPT',
      note: REGRESSION_MARKER,
    }],
    receiptFileId: null,
  });
  assert.doesNotThrow(() => replay.assertManualApproveReplay(200, 200, detail, detail));
});

test('assertReceiptThenManualConflict rejects replay 200', () => {
  assert.throws(
    () => replay.assertReceiptThenManualConflict(200, 'SETTLEMENT_ALREADY_APPROVED'),
    /must not return replay 200/,
  );
});

test('assertReceiptThenManualConflict accepts semantic conflict codes', () => {
  assert.doesNotThrow(() => replay.assertReceiptThenManualConflict(409, 'SETTLEMENT_ALREADY_APPROVED'));
  assert.doesNotThrow(() => replay.assertReceiptThenManualConflict(409, 'SETTLEMENT_MANUAL_APPROVAL_NOT_ALLOWED'));
});

test('assertManualThenUploadConflict requires RECEIPT_ALREADY_APPROVED', () => {
  assert.doesNotThrow(() => replay.assertManualThenUploadConflict(409, 'RECEIPT_ALREADY_APPROVED'));
  assert.throws(
    () => replay.assertManualThenUploadConflict(409, 'SETTLEMENT_ALREADY_APPROVED'),
    /RECEIPT_ALREADY_APPROVED/,
  );
});

test('assertManualPreconditions enforces manual-approve gate', () => {
  assert.doesNotThrow(() => replay.assertManualPreconditions({
    canManualApprove: true,
    receiptFileId: null,
    commissionAmount: 120,
  }));
  assert.throws(
    () => replay.assertManualPreconditions({ canManualApprove: false, commissionAmount: 120 }),
    /canManualApprove=true/,
  );
  assert.throws(
    () => replay.assertManualPreconditions({ canManualApprove: true, receiptFileId: 1, commissionAmount: 120 }),
    /receiptFileId absent/,
  );
});

test('parseReportFromLog extracts replay report fields', () => {
  const log = JSON.stringify({
    RECEIPT_BOOKING: 'TX202608150019',
    RECEIPT_APPROVE_FIRST_STATUS: 200,
    RECEIPT_APPROVE_RETRY_STATUS: 200,
    RECEIPT_THEN_MANUAL_STATUS: 409,
    RECEIPT_THEN_MANUAL_ERROR: 'SETTLEMENT_ALREADY_APPROVED',
    MANUAL_BOOKING: 'TX202608150020',
    MANUAL_THEN_UPLOAD_STATUS: 409,
    MANUAL_THEN_UPLOAD_ERROR: 'RECEIPT_ALREADY_APPROVED',
  }, null, 2);
  const parsed = replay.parseReportFromLog(log);
  assert.equal(parsed.RECEIPT_BOOKING, 'TX202608150019');
  assert.equal(parsed.RECEIPT_APPROVE_FIRST_STATUS, 200);
  assert.equal(parsed.RECEIPT_THEN_MANUAL_ERROR, 'SETTLEMENT_ALREADY_APPROVED');
  assert.equal(parsed.MANUAL_BOOKING, 'TX202608150020');
  assert.equal(parsed.MANUAL_THEN_UPLOAD_ERROR, 'RECEIPT_ALREADY_APPROVED');
});

test('parseDbCheckRow and receipt DB side-effect assertions', () => {
  const row = replay.parseDbCheckRow('COMPLETED\tPAID\t1\t1\t0\t1\t0\t1');
  assert.doesNotThrow(() => replay.assertReceiptDbSideEffects(row));
});

test('parseDbCheckRow and manual DB side-effect assertions', () => {
  const row = replay.parseDbCheckRow('COMPLETED\tPAID\t1\t0\t1\t1\t0\t0');
  assert.doesNotThrow(() => replay.assertManualDbSideEffects(row));
});

test('cleanup helper format remains compatible with partial failure logging', () => {
  assert.equal(
    cleanup.formatCleanupFailure('TX202608150019', 'archive failed'),
    'CLEANUP_FAILED booking=TX202608150019 reason=archive failed',
  );
});

test('partial failure cleanup targets bookings recorded only in report', () => {
  const report = replay.createEmptyReport();
  report.RECEIPT_BOOKING = 'TX202608150019';
  report.MANUAL_BOOKING = 'TX202608150020';
  const records = [{ bookingNumber: 'TX202608150019', payload: replay.receiptBookingPayload() }];
  const seen = new Set(records.map((record) => record.bookingNumber));
  const cleanupTargets = [...records];
  if (report.MANUAL_BOOKING && !seen.has(report.MANUAL_BOOKING)) {
    cleanupTargets.push({ bookingNumber: report.MANUAL_BOOKING, payload: replay.manualBookingPayload() });
  }
  assert.equal(cleanupTargets.length, 2);
  assert.equal(cleanupTargets[1].bookingNumber, 'TX202608150020');
});
