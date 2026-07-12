process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const BOOKING_STATUS = require('../src/constants/reservationStatus');
const {
  isDatabaseOrInternalError,
  resolveClientErrorMessage,
  isTripEndRequest,
  TRIP_END_FAILURE_MESSAGE,
  GENERIC_INTERNAL_MESSAGE,
} = require('../src/utils/clientErrorMessage.util');
const AppError = require('../src/utils/AppError');
const ERROR_CODES = require('../src/constants/errorCodes');
const HTTP_STATUS = require('../src/constants/httpStatus');

test('isDatabaseOrInternalError detects mysql truncation errors', () => {
  const err = new Error("Data truncated for column 'status' at row 1");
  err.code = 'WARN_DATA_TRUNCATED';
  assert.equal(isDatabaseOrInternalError(err), true);
});

test('isDatabaseOrInternalError ignores operational AppError', () => {
  const err = new AppError('Invalid booking status transition', {
    statusCode: HTTP_STATUS.CONFLICT,
    errorCode: ERROR_CODES.INVALID_STATUS_TRANSITION,
  });
  assert.equal(isDatabaseOrInternalError(err), false);
});

test('resolveClientErrorMessage keeps operational messages', () => {
  const err = new AppError('Booking not found', {
    statusCode: HTTP_STATUS.NOT_FOUND,
    errorCode: ERROR_CODES.BOOKING_NOT_FOUND,
  });
  assert.equal(resolveClientErrorMessage(err), 'Booking not found');
});

test('resolveClientErrorMessage hides raw database text', () => {
  const err = new Error("Data truncated for column 'status' at row 1");
  assert.equal(resolveClientErrorMessage(err), GENERIC_INTERNAL_MESSAGE);
  assert.equal(
    resolveClientErrorMessage(err, { tripEndFailure: true }),
    TRIP_END_FAILURE_MESSAGE,
  );
});

test('isTripEndRequest matches driver end-trip route', () => {
  assert.equal(
    isTripEndRequest({ path: '/api/v1/driver/bookings/TX202607120002/end-trip' }),
    true,
  );
  assert.equal(
    isTripEndRequest({ path: '/api/v1/driver/bookings/TX202607120002/start-on-route' }),
    false,
  );
});

test('migration 37 includes every booking status and is idempotent', () => {
  const migrationPath = path.resolve(
    __dirname,
    '..',
    '..',
    'database',
    '37_add_settlement_pending_booking_status.sql',
  );
  const sql = fs.readFileSync(migrationPath, 'utf8');

  assert.match(sql, /SETTLEMENT_PENDING/);
  assert.match(sql, /information_schema\.COLUMNS/);
  assert.match(sql, /NOT LIKE '%SETTLEMENT_PENDING%'/);
  assert.doesNotMatch(sql, /USE ttaxi/i);
  assert.doesNotMatch(sql, /USE tride_staging/i);

  for (const status of Object.values(BOOKING_STATUS)) {
    assert.match(sql, new RegExp(`'${status}'`));
  }

  assert.equal((sql.match(/ALTER TABLE bookings/g) || []).length, 1);
  assert.equal((sql.match(/booking_status_logs/g) || []).length, 4);
});
