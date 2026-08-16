process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'tride_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const assert = require('node:assert/strict');

const harness = require('../scripts/staging-contact-dispatch-durable-e2e');
const { createBookingSchema } = require('../src/validators/booking.validator');
const { REGRESSION_MARKER } = require('../scripts/staging-booking-regression');

test('contact dispatch durable E2E payload uses regression cleanup marker', () => {
  const payload = harness.bookingPayload();
  assert.equal(payload.additionalRequests, REGRESSION_MARKER);
  assert.match(payload.customer.name, /^\[E2E\]/);
  const { error } = createBookingSchema.validate(payload, { abortEarly: false });
  assert.equal(error, undefined);
});

test('harness exports deterministic booking marker constant', () => {
  assert.equal(harness.E2E_MARKER, 'CONTACT_DISPATCH_DURABLE_E2E');
  assert.equal(harness.CUSTOMER_NAME, '[E2E] Contact Dispatch Durable');
});

test('staging contact dispatch durable runner uses safe env hygiene and EXIT cleanup', () => {
  const runnerPath = path.resolve(
    __dirname,
    '../scripts/run-staging-contact-dispatch-durable-e2e.sh',
  );
  const contents = fs.readFileSync(runnerPath, 'utf8');

  assert.match(contents, /set -eu/);
  assert.match(contents, /trap cleanup EXIT/);
  assert.match(contents, /local rc=\$\?/);
  assert.match(contents, /exit "\$rc"/);
  assert.match(contents, /rm -f \/srv\/tride\/\.env\.e2e\.local/);
  assert.match(contents, /read_env\(\)/);
  assert.match(contents, /docker cp \/opt\/t-ride\/\.env\.e2e\.local tride-backend:\/srv\/tride\/\.env\.e2e\.local/);
  assert.match(contents, /TRIDE_BASE_URL=https:\/\/trider\.taxi/);
  assert.match(contents, /TRIDE_ALLOW_LIVE_BOOKING_REGRESSION=1/);
  assert.match(contents, /provision-staging-test-accounts\.js/);
  assert.match(contents, /CONTACT_DISPATCH_E2E_BOOKING=/);
  assert.match(contents, /run-staging-contact-dispatch-durable-db-check\.sh/);

  assert.doesNotMatch(contents, /source \/opt\/t-ride\/\.env\.e2e\.local/);
  assert.doesNotMatch(contents, /source .*\.env\.e2e\.local/);
  assert.doesNotMatch(contents, /echo.*PASSWORD/i);
  assert.doesNotMatch(contents, /printf.*PASSWORD/i);
  assert.doesNotMatch(contents, /echo.*TOKEN/i);
});

test('staging contact dispatch durable db-check runner is SELECT-only', () => {
  const runnerPath = path.resolve(
    __dirname,
    '../scripts/run-staging-contact-dispatch-durable-db-check.sh',
  );
  const sqlPath = path.resolve(
    __dirname,
    '../scripts/staging-contact-dispatch-durable-db-check.sql',
  );
  const runner = fs.readFileSync(runnerPath, 'utf8');
  const sql = fs.readFileSync(sqlPath, 'utf8');

  assert.match(runner, /BOOKING="\$\{1:\?booking number required\}"/);
  assert.match(runner, /source \/opt\/t-ride\/deploy\/docker\/\.env/);
  assert.match(runner, /staging-contact-dispatch-durable-db-check\.sql/);
  assert.doesNotMatch(runner, /echo.*PASSWORD/i);

  assert.doesNotMatch(sql, /\bINSERT\b/i);
  assert.doesNotMatch(sql, /\bUPDATE\b/i);
  assert.doesNotMatch(sql, /\bDELETE\b/i);
  assert.doesNotMatch(sql, /\bDROP\b/i);
  assert.doesNotMatch(sql, /\bALTER\b/i);
  assert.match(sql, /contact_dispatch_completed/);
  assert.match(sql, /contact_dispatch_delivered/);
  assert.match(sql, /duplicate_idempotency_key_count/);
  assert.match(sql, /active_assignment_count/);
  assert.match(sql, /recipient_driver_id/);
});

test('harness success output includes deterministic booking marker line', () => {
  const harnessPath = path.resolve(
    __dirname,
    '../scripts/staging-contact-dispatch-durable-e2e.js',
  );
  const contents = fs.readFileSync(harnessPath, 'utf8');
  assert.match(contents, /console\.log\(`CONTACT_DISPATCH_E2E_BOOKING=\$\{bookingNumber\}`\)/);
  assert.match(contents, /cleanupRegressionBookings/);
  assert.doesNotMatch(contents, /console\.log\(.*PASSWORD/i);
});
