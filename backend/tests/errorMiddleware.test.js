process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const { test } = require('node:test');
const assert = require('node:assert/strict');

const errorMiddleware = require('../src/middlewares/error.middleware');
const ERROR_CODES = require('../src/constants/errorCodes');

function createResponse() {
  const res = {
    headersSent: false,
    statusCode: null,
    body: null,
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(payload) {
      this.body = payload;
      return this;
    },
  };
  return res;
}

test('error middleware hides mysql truncation text on end-trip route', () => {
  const err = new Error("Data truncated for column 'status' at row 1");
  err.code = 'WARN_DATA_TRUNCATED';
  const req = { path: '/api/v1/driver/bookings/TX202607120002/end-trip', method: 'POST' };
  const res = createResponse();
  let nextCalled = false;

  errorMiddleware(err, req, res, () => {
    nextCalled = true;
  });

  assert.equal(nextCalled, false);
  assert.equal(res.statusCode, 500);
  assert.equal(res.body.error_code, ERROR_CODES.INTERNAL_SERVER_ERROR);
  assert.equal(
    res.body.message,
    'We could not complete the trip. Please try again or contact an administrator.',
  );
  assert.equal(res.body.message.includes('status'), false);
  assert.equal(res.body.stack, undefined);
});

test('error middleware keeps operational validation messages', () => {
  const err = new (require('../src/utils/AppError'))('Invalid booking status transition', {
    statusCode: 409,
    errorCode: ERROR_CODES.INVALID_STATUS_TRANSITION,
  });
  const req = { path: '/api/v1/driver/bookings/TX202607120002/end-trip', method: 'POST' };
  const res = createResponse();

  errorMiddleware(err, req, res, () => {});

  assert.equal(res.statusCode, 409);
  assert.equal(res.body.message, 'Invalid booking status transition');
  assert.equal(res.body.error_code, ERROR_CODES.INVALID_STATUS_TRANSITION);
});
