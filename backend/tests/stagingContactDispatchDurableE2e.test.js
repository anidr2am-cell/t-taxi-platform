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
const NOTIFICATION_TYPES = require('../src/constants/notificationTypes');
const { createBookingSchema } = require('../src/validators/booking.validator');
const {
  REGRESSION_MARKER,
  toPricingPayload,
  assertValidBookingPayload,
  TEST_NAME_PREFIX,
} = require('../scripts/staging-booking-regression');
const cleanup = require('../scripts/e2eRegressionCleanup');

test('contact dispatch durable E2E payload uses regression cleanup marker', () => {
  const payload = harness.bookingPayload();
  assert.equal(payload.additionalRequests, REGRESSION_MARKER);
  assert.match(payload.customer.name, /^\[E2E\]/);
  assert.equal(payload.serviceTypeCode, 'AIRPORT_PICKUP');
  assert.equal(payload.vehicleTypeCode, 'SUV');
  assert.equal(payload.originAirportIata, 'BKK');
  assert.equal(payload.destinationLocationCode, 'PATTAYA');
  assert.equal(payload.bookingMode, undefined);
  const { error } = createBookingSchema.validate(payload, { abortEarly: false });
  assert.equal(error, undefined);
});

test('actual POST /api/v1/bookings request body matches booking create contract', () => {
  const payload = harness.bookingPayload();
  const requestPayload = harness.buildCreateBookingRequest(payload);
  assert.doesNotThrow(
    () => assertValidBookingPayload(requestPayload, 'contact dispatch durable request'),
  );
  assert.equal(requestPayload.customer.name, harness.CUSTOMER_NAME);
  assert.ok(requestPayload.origin);
  assert.ok(requestPayload.destination);
  assert.ok(requestPayload.customer);

  const pricingOnly = toPricingPayload(requestPayload);
  const { error } = createBookingSchema.validate(pricingOnly, { abortEarly: false });
  assert.notEqual(error, undefined);
  assert.ok(error.details.some((detail) => detail.path.join('.') === 'origin'));
  assert.ok(error.details.some((detail) => detail.path.join('.') === 'destination'));
  assert.ok(error.details.some((detail) => detail.path.join('.') === 'customer'));
});

test('create booking failure formatting includes safe validation details only', () => {
  const formatted = harness.formatCreateBookingFailure({
    status: 400,
    body: {
      error_code: 'VALIDATION_ERROR',
      errors: [
        { field: 'customer.phone', type: 'any.required', source: 'body' },
        { field: 'origin', type: 'any.required', source: 'body' },
      ],
    },
  });
  assert.match(formatted, /Create booking failed: HTTP 400 VALIDATION_ERROR/);
  assert.match(formatted, /customer\.phone:any\.required:body/);
  assert.match(formatted, /origin:any\.required:body/);
  assert.doesNotMatch(formatted, /guestAccessToken/i);
  assert.doesNotMatch(formatted, /password/i);
  assert.doesNotMatch(formatted, /token/i);
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
  assert.match(sql, /booking_id/);
  assert.match(sql, /expected_key/);
  assert.match(sql, /key_matches/);
});

test('harness success output includes deterministic booking marker line', () => {
  const harnessPath = path.resolve(
    __dirname,
    '../scripts/staging-contact-dispatch-durable-e2e.js',
  );
  const contents = fs.readFileSync(harnessPath, 'utf8');
  assert.match(contents, /console\.log\(`CONTACT_DISPATCH_E2E_BOOKING=\$\{bookingNumber\}`\)/);
  assert.match(contents, /JSON\.stringify\(requestPayload\)/);
  assert.match(contents, /toPricingPayload\(requestPayload\)/);
  assert.match(contents, /assertTestDriverEligibleForNewJob/);
  assert.match(contents, /\/api\/v1\/driver\/online/);
  assert.match(contents, /Expected exactly one DRIVER_CALL_AVAILABLE notification for E2E driver/);
  assert.match(contents, /FIRST_VERIFY_DISPATCH_STARTED !== true/);
  assert.match(contents, /CLEANUP_API_BASED=YES/);
  assert.match(contents, /formatCleanupFailure\(bookingNumber, cleanupErr\.message\)/);
  assert.doesNotMatch(contents, /cleanup\.ok/);
  assert.doesNotMatch(contents, /Admin booking detail missing booking id/);
  assert.doesNotMatch(contents, /fetchAdminBookingDetail/);
  assert.match(contents, /EXPECTED_IDEMPOTENCY_KEY_PATTERN/);
  assert.doesNotMatch(contents, /JSON\.stringify\(toPricingPayload\(payload\)\)/);
  assert.match(contents, /cleanupRegressionBookings/);
  assert.doesNotMatch(contents, /console\.log\(.*PASSWORD/i);
});

test('countTargetDriverCallNotifications uses notificationType and bookingNumber', () => {
  const bookingNumber = 'TX202608160001';
  const items = [
    {
      notificationType: NOTIFICATION_TYPES.DRIVER_CALL_AVAILABLE,
      payload: { bookingNumber },
    },
    {
      notificationType: NOTIFICATION_TYPES.DRIVER_CALL_AVAILABLE,
      payload: { bookingNumber: 'TX202608169999' },
    },
    {
      type: NOTIFICATION_TYPES.DRIVER_CALL_AVAILABLE,
      payload: { bookingNumber },
    },
  ];
  assert.equal(harness.countTargetDriverCallNotifications(items, bookingNumber), 1);
});

test('buildContactDispatchIdempotencyKey follows driver-call-open convention', () => {
  assert.equal(
    harness.buildContactDispatchIdempotencyKey(42, 11),
    'driver-call-open:42:11',
  );
});

test('buildContactDispatchIdempotencyKeyPattern documents unresolved internal booking id', () => {
  assert.equal(
    harness.buildContactDispatchIdempotencyKeyPattern(),
    'driver-call-open:<bookingId>:<driverId>',
  );
});

test('harness does not require admin booking detail internal id before verify', () => {
  const harnessPath = path.resolve(
    __dirname,
    '../scripts/staging-contact-dispatch-durable-e2e.js',
  );
  const contents = fs.readFileSync(harnessPath, 'utf8');
  const createIndex = contents.indexOf("fetchJson(baseUrl, '/api/v1/bookings',");
  const verifyIndex = contents.indexOf('const firstVerify = await verifyContact');
  assert.ok(createIndex >= 0);
  assert.ok(verifyIndex >= 0);
  assert.ok(createIndex < verifyIndex);
  assert.doesNotMatch(contents, /bookingDetail\.id/);
  assert.doesNotMatch(contents, /bookingDetail\.bookingId/);
});

test('runApiCleanup prints PASS markers after successful cleanupRegressionBookings', () => {
  const harnessPath = path.resolve(
    __dirname,
    '../scripts/staging-contact-dispatch-durable-e2e.js',
  );
  const contents = fs.readFileSync(harnessPath, 'utf8');
  assert.match(contents, /async function runApiCleanup/);
  assert.match(contents, /await cleanupRegressionBookings/);
  assert.match(contents, /CLEANUP_API_BASED=YES/);
  assert.match(contents, /CLEANUP_RESULT=PASS/);
  assert.doesNotMatch(contents, /cleanup\.ok/);
});

test('cleanup still runs in finally after later API failure', () => {
  const harnessPath = path.resolve(
    __dirname,
    '../scripts/staging-contact-dispatch-durable-e2e.js',
  );
  const contents = fs.readFileSync(harnessPath, 'utf8');
  const finallyIndex = contents.indexOf('} finally {');
  const cleanupIndex = contents.indexOf('await runApiCleanup');
  assert.ok(finallyIndex >= 0);
  assert.ok(cleanupIndex > finallyIndex);
  assert.match(contents, /if \(bookingNumber && adminToken && driverToken\)/);
});

test('formatCleanupFailure uses booking number and safe reason text', () => {
  assert.equal(
    cleanup.formatCleanupFailure('TX202608160001', 'archive refused'),
    'CLEANUP_FAILED booking=TX202608160001 reason=archive refused',
  );
});

test('countTargetDriverCallNotifications only counts matching booking for target driver list', () => {
  const bookingNumber = 'TX202608160001';
  const sameDriverItems = [
    {
      notificationType: NOTIFICATION_TYPES.DRIVER_CALL_AVAILABLE,
      payload: { bookingNumber },
    },
    {
      notificationType: NOTIFICATION_TYPES.DRIVER_CALL_AVAILABLE,
      payload: { bookingNumber: 'TX202608169999' },
    },
  ];
  assert.equal(harness.countTargetDriverCallNotifications(sameDriverItems, bookingNumber), 1);
  assert.equal(
    harness.countTargetDriverCallNotifications(
      [{ notificationType: NOTIFICATION_TYPES.DRIVER_CALL_AVAILABLE, payload: { bookingNumber: 'TX999' } }],
      bookingNumber,
    ),
    0,
  );
});

test('harness checks driver eligibility before booking creation', () => {
  const harnessPath = path.resolve(
    __dirname,
    '../scripts/staging-contact-dispatch-durable-e2e.js',
  );
  const contents = fs.readFileSync(harnessPath, 'utf8');
  const eligibilityIndex = contents.indexOf('assertTestDriverEligibleForNewJob');
  const createIndex = contents.indexOf("fetchJson(baseUrl, '/api/v1/bookings',");
  assert.ok(eligibilityIndex >= 0);
  assert.ok(createIndex >= 0);
  assert.ok(eligibilityIndex < createIndex);
});

test('assertTestDriverEligibleForNewJob fails early when driver is not assignment eligible', async () => {
  const originalFetch = global.fetch;
  global.fetch = async (url) => {
    if (String(url).endsWith('/api/v1/admin/drivers')) {
      return {
        ok: true,
        status: 200,
        text: async () => JSON.stringify({
          data: {
            items: [{
              id: 11,
              displayName: `${TEST_NAME_PREFIX} Regression Driver`,
              assignmentEligible: false,
              eligibilityState: 'OFFLINE',
              activeAssignmentCount: 0,
            }],
          },
        }),
      };
    }
    throw new Error(`Unexpected fetch: ${url}`);
  };
  try {
    await assert.rejects(
      () => cleanup.assertTestDriverEligibleForNewJob('https://trider.taxi', 'admin-token'),
      /not assignment eligible/,
    );
  } finally {
    global.fetch = originalFetch;
  }
});

test('printSafeDiagnostics excludes secrets and includes dispatch diagnostics', () => {
  const logs = [];
  const originalLog = console.log;
  console.log = (...args) => logs.push(args.join(' '));
  try {
    harness.printSafeDiagnostics({
      BOOKING: 'TX202608160001',
      TEST_DRIVER_ID: 11,
      TEST_DRIVER_ELIGIBLE: true,
      FIRST_VERIFY_STATUS: 200,
      FIRST_VERIFY_DISPATCH_STARTED: true,
      OPEN_CALL_VISIBLE_AFTER_FIRST_VERIFY: true,
      EXPECTED_IDEMPOTENCY_KEY_PATTERN: 'driver-call-open:<bookingId>:<driverId>',
      FIRST_TARGET_DRIVER_NOTIFICATION_COUNT: 1,
      RETRY_TARGET_DRIVER_NOTIFICATION_COUNT: 1,
    });
  } finally {
    console.log = originalLog;
  }
  const joined = logs.join('\n');
  assert.match(joined, /BOOKING=TX202608160001/);
  assert.match(joined, /FIRST_VERIFY_DISPATCH_STARTED=true/);
  assert.match(joined, /TEST_DRIVER_ELIGIBLE=true/);
  assert.match(joined, /EXPECTED_IDEMPOTENCY_KEY_PATTERN=driver-call-open:<bookingId>:<driverId>/);
  assert.match(joined, /RETRY_TARGET_DRIVER_NOTIFICATION_COUNT=1/);
  assert.doesNotMatch(joined, /token/i);
  assert.doesNotMatch(joined, /password/i);
});
