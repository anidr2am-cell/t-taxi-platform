process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'tride_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const assert = require('node:assert/strict');

const harness = require('../scripts/staging-urgent-timeout-hardening-e2e');
const { createBookingSchema } = require('../src/validators/booking.validator');
const { REGRESSION_MARKER } = require('../scripts/staging-booking-regression');
const { parseServiceDateTimeToMs } = require('../src/utils/serviceDateTime.util');

test('timeout hardening E2E payload uses regression cleanup marker and URGENT mode', () => {
  const payload = harness.bookingPayload();
  assert.equal(payload.additionalRequests, REGRESSION_MARKER);
  assert.equal(payload.bookingMode, 'URGENT');
  assert.match(payload.customer.name, /^\[E2E\]/);
  const { error } = createBookingSchema.validate(payload, { abortEarly: false });
  assert.equal(error, undefined);
});

test('expiredNowMs returns a timestamp after the provided expiry', () => {
  const expiry = '2099-07-23 01:29:00.000';
  const nowMs = harness.expiredNowMs(expiry);
  const expiresMs = parseServiceDateTimeToMs(expiry);
  assert.ok(nowMs > expiresMs);
});

test('expiredNowMs rejects invalid expiry timestamps', () => {
  assert.throws(
    () => harness.expiredNowMs('not-a-date'),
    /Invalid expiry timestamp/,
  );
});

test('workerConfigReport exposes only non-secret timeout worker settings', () => {
  process.env.URGENT_NEGOTIATION_TIMEOUT_ENABLED = 'true';
  process.env.URGENT_NEGOTIATION_TIMEOUT_INTERVAL_MS = '30000';
  process.env.URGENT_NEGOTIATION_TIMEOUT_BATCH_SIZE = '20';
  const report = harness.workerConfigReport();
  assert.equal(report.URGENT_NEGOTIATION_TIMEOUT_ENABLED, 'true');
  assert.equal(report.URGENT_NEGOTIATION_TIMEOUT_INTERVAL_MS, '30000');
  assert.equal(report.URGENT_NEGOTIATION_TIMEOUT_BATCH_SIZE, '20');
  assert.equal(report.TRIDE_ADMIN_PASSWORD, undefined);
});

test('harness exports regression marker constant for cleanup safety checks', () => {
  assert.equal(harness.REGRESSION_MARKER, 'AUTOMATED_REGRESSION_TEST');
});

test('staging timeout hardening runner removes copied E2E env on EXIT', () => {
  const runnerPath = path.resolve(
    __dirname,
    '../scripts/run-staging-urgent-timeout-hardening-e2e.sh',
  );
  const contents = fs.readFileSync(runnerPath, 'utf8');
  assert.match(contents, /trap cleanup EXIT/);
  assert.match(contents, /rm -f \/srv\/tride\/\.env\.e2e\.local/);
  assert.match(contents, /local rc=\$\?/);
  assert.match(contents, /exit "\$rc"/);
  assert.doesNotMatch(contents, /^docker exec tride-backend rm -f \/srv\/tride\/\.env\.e2e\.local$/m);
});
