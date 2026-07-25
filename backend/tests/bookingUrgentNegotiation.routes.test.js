const { test } = require('node:test');
const assert = require('node:assert/strict');
const jwt = require('jsonwebtoken');
const request = require('supertest');

process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const AppError = require('../src/utils/AppError');
const ERROR_CODES = require('../src/constants/errorCodes');
const HTTP_STATUS = require('../src/constants/httpStatus');
const container = require('../src/helpers/container');
const app = require('../src/app');

const BOOKING_NUMBER = 'TX202607230001';

function sign(role = 'CUSTOMER', id = 99) {
  return jwt.sign(
    { sub: id, email: `${role.toLowerCase()}@example.com`, role, type: 'access' },
    process.env.JWT_ACCESS_SECRET,
    { expiresIn: '1h' },
  );
}

function registerUrgentNegotiationService(handlers = {}) {
  container.register('urgentNegotiationService', () => ({
    async submitCustomerDecision(bookingNumber, decision, options) {
      if (handlers.submitCustomerDecision) {
        return handlers.submitCustomerDecision(bookingNumber, decision, options);
      }
      throw new Error('submitCustomerDecision should not be called in this test');
    },
    async getCustomerNegotiationStatus(bookingNumber, options) {
      if (handlers.getCustomerNegotiationStatus) {
        return handlers.getCustomerNegotiationStatus(bookingNumber, options);
      }
      throw new Error('getCustomerNegotiationStatus should not be called in this test');
    },
  }));
}

test('GET /bookings/:bookingNumber/urgent-negotiation returns current status', async () => {
  registerUrgentNegotiationService({
    async getCustomerNegotiationStatus(bookingNumber, options) {
      assert.equal(bookingNumber, BOOKING_NUMBER);
      assert.equal(options.guestAccessToken, 'guest-token-value');
      return {
        bookingNumber,
        bookingId: 10,
        bookingStatus: 'OPEN',
        negotiationId: 100,
        status: 'BROADCASTING',
        attemptCount: 0,
      };
    },
  });

  const res = await request(app)
    .get(`/api/v1/bookings/${BOOKING_NUMBER}/urgent-negotiation`)
    .set('X-Guest-Access-Token', 'guest-token-value');

  assert.equal(res.status, 200);
  assert.equal(res.body.data.status, 'BROADCASTING');
});

test('POST /bookings/:bookingNumber/urgent-decision returns 200 with negotiation payload', async () => {
  let capturedBookingNumber = null;
  let capturedDecision = null;
  let capturedOptions = null;

  registerUrgentNegotiationService({
    async submitCustomerDecision(bookingNumber, decision, options) {
      capturedBookingNumber = bookingNumber;
      capturedDecision = decision;
      capturedOptions = options;
      return {
        bookingNumber,
        bookingId: 10,
        negotiationId: 100,
        status: 'CONFIRMED',
        decision: 'ACCEPT',
        assignmentId: 9001,
        bookingStatus: 'DRIVER_ASSIGNED',
      };
    },
  });

  const res = await request(app)
    .post(`/api/v1/bookings/${BOOKING_NUMBER}/urgent-decision`)
    .set('Authorization', `Bearer ${sign('CUSTOMER', 99)}`)
    .send({ decision: 'ACCEPT' });

  assert.equal(res.status, 200);
  assert.equal(res.body.success, true);
  assert.equal(capturedBookingNumber, BOOKING_NUMBER);
  assert.equal(capturedDecision, 'ACCEPT');
  assert.equal(capturedOptions.authUser.id, 99);
  assert.equal(res.body.data.status, 'CONFIRMED');
  assert.equal(res.body.data.assignmentId, 9001);
});

test('POST /bookings/:bookingNumber/urgent-decision returns 409 when not awaiting customer', async () => {
  registerUrgentNegotiationService({
    async submitCustomerDecision() {
      throw new AppError('Urgent negotiation is not awaiting customer decision', {
        statusCode: HTTP_STATUS.CONFLICT,
        errorCode: ERROR_CODES.URGENT_NEGOTIATION_NOT_AWAITING,
      });
    },
  });

  const res = await request(app)
    .post(`/api/v1/bookings/${BOOKING_NUMBER}/urgent-decision`)
    .set('Authorization', `Bearer ${sign('CUSTOMER', 99)}`)
    .send({ decision: 'REJECT' });

  assert.equal(res.status, 409);
  assert.equal(res.body.error_code, ERROR_CODES.URGENT_NEGOTIATION_NOT_AWAITING);
});

test('POST /bookings/:bookingNumber/urgent-decision returns 409 when decision window expired', async () => {
  registerUrgentNegotiationService({
    async submitCustomerDecision() {
      throw new AppError('Customer decision window has expired', {
        statusCode: HTTP_STATUS.CONFLICT,
        errorCode: ERROR_CODES.URGENT_DECISION_WINDOW_EXPIRED,
      });
    },
  });

  const res = await request(app)
    .post(`/api/v1/bookings/${BOOKING_NUMBER}/urgent-decision`)
    .set('Authorization', `Bearer ${sign('CUSTOMER', 99)}`)
    .send({ decision: 'ACCEPT' });

  assert.equal(res.status, 409);
  assert.equal(res.body.error_code, ERROR_CODES.URGENT_DECISION_WINDOW_EXPIRED);
});

test('POST /bookings/:bookingNumber/urgent-decision rejects invalid decision with 400', async () => {
  registerUrgentNegotiationService({
    async submitCustomerDecision() {
      throw new Error('submitCustomerDecision should not be called when body validation fails');
    },
  });

  const res = await request(app)
    .post(`/api/v1/bookings/${BOOKING_NUMBER}/urgent-decision`)
    .set('Authorization', `Bearer ${sign('CUSTOMER', 99)}`)
    .send({ decision: 'MAYBE' });

  assert.equal(res.status, 400);
  assert.equal(res.body.error_code, ERROR_CODES.VALIDATION_ERROR);
});

test('POST /bookings/:bookingNumber/urgent-decision passes guest token from header', async () => {
  let capturedOptions = null;

  registerUrgentNegotiationService({
    async submitCustomerDecision(_bookingNumber, _decision, options) {
      capturedOptions = options;
      return {
        bookingNumber: BOOKING_NUMBER,
        status: 'BROADCASTING',
        decision: 'REJECT',
      };
    },
  });

  const res = await request(app)
    .post(`/api/v1/bookings/${BOOKING_NUMBER}/urgent-decision`)
    .set('X-Guest-Access-Token', 'guest-token-value')
    .send({ decision: 'REJECT' });

  assert.equal(res.status, 200);
  assert.equal(capturedOptions.guestAccessToken, 'guest-token-value');
  assert.equal(capturedOptions.authUser, null);
});

test('POST /bookings/:bookingNumber/urgent-decision returns 403 when booking is not accessible', async () => {
  registerUrgentNegotiationService({
    async submitCustomerDecision() {
      throw new AppError('Booking is not accessible', {
        statusCode: HTTP_STATUS.FORBIDDEN,
        errorCode: ERROR_CODES.BOOKING_NOT_ACCESSIBLE,
      });
    },
  });

  const res = await request(app)
    .post(`/api/v1/bookings/${BOOKING_NUMBER}/urgent-decision`)
    .send({ decision: 'ACCEPT' });

  assert.equal(res.status, 403);
  assert.equal(res.body.error_code, ERROR_CODES.BOOKING_NOT_ACCESSIBLE);
});
