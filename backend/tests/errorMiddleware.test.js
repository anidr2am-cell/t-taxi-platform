process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const { test } = require('node:test');
const assert = require('node:assert/strict');

const errorMiddleware = require('../src/middlewares/error.middleware');
const ERROR_CODES = require('../src/constants/errorCodes');
const AppError = require('../src/utils/AppError');
const config = require('../src/config');

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
  const err = new AppError('Invalid booking status transition', {
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

test('error middleware exposes validation error details in production', () => {
  const originalNodeEnv = config.server.nodeEnv;
  config.server.nodeEnv = 'production';
  try {
    const err = new AppError('Validation failed', {
      statusCode: 400,
      errorCode: ERROR_CODES.VALIDATION_ERROR,
      errors: [
        {
          field: 'customer.name',
          type: 'string.empty',
          message: '"customer.name" is not allowed to be empty',
          source: 'body',
        },
      ],
    });
    const req = { path: '/api/v1/bookings', method: 'POST' };
    const res = createResponse();

    errorMiddleware(err, req, res, () => {});

    assert.equal(res.statusCode, 400);
    assert.equal(res.body.error_code, ERROR_CODES.VALIDATION_ERROR);
    assert.equal(res.body.errors[0].field, 'customer.name');
    assert.equal(res.body.errors[0].type, 'string.empty');
  } finally {
    config.server.nodeEnv = originalNodeEnv;
  }
});
