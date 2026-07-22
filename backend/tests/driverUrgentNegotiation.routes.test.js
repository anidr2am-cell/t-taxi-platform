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

function sign(role = 'DRIVER', id = 44) {
  return jwt.sign(
    { sub: id, email: `${role.toLowerCase()}@example.com`, role, type: 'access' },
    process.env.JWT_ACCESS_SECRET,
    { expiresIn: '1h' },
  );
}

function registerUrgentNegotiationService(handlers = {}) {
  container.register('urgentNegotiationService', () => ({
    async lockNegotiation(driverUserId, bookingNumber) {
      if (handlers.lockNegotiation) {
        return handlers.lockNegotiation(driverUserId, bookingNumber);
      }
      throw new Error('lockNegotiation should not be called in this test');
    },
    async submitEta(driverUserId, bookingNumber, etaMinutes) {
      if (handlers.submitEta) {
        return handlers.submitEta(driverUserId, bookingNumber, etaMinutes);
      }
      throw new Error('submitEta should not be called in this test');
    },
  }));
}

test('POST /driver/urgent-calls/:bookingNumber/lock returns 200 with negotiation payload', async () => {
  let capturedUserId = null;
  let capturedBookingNumber = null;

  registerUrgentNegotiationService({
    async lockNegotiation(driverUserId, bookingNumber) {
      capturedUserId = driverUserId;
      capturedBookingNumber = bookingNumber;
      return {
        bookingNumber,
        bookingId: 10,
        negotiationId: 100,
        attemptId: 1,
        attemptNumber: 1,
        driverId: 7,
        status: 'LOCKED',
        lockExpiresAt: '2026-07-23 01:30:00.000',
      };
    },
  });

  const res = await request(app)
    .post(`/api/v1/driver/urgent-calls/${BOOKING_NUMBER}/lock`)
    .set('Authorization', `Bearer ${sign('DRIVER', 44)}`);

  assert.equal(res.status, 200);
  assert.equal(res.body.success, true);
  assert.equal(capturedUserId, 44);
  assert.equal(capturedBookingNumber, BOOKING_NUMBER);
  assert.equal(res.body.data.status, 'LOCKED');
  assert.equal(res.body.data.attemptNumber, 1);
  assert.equal(res.body.data.lockExpiresAt, '2026-07-23 01:30:00.000');
});

test('POST /driver/urgent-calls/:bookingNumber/lock returns 409 when negotiation is not lockable', async () => {
  registerUrgentNegotiationService({
    async lockNegotiation() {
      throw new AppError('Another driver has already locked this urgent call', {
        statusCode: HTTP_STATUS.CONFLICT,
        errorCode: ERROR_CODES.URGENT_ALREADY_LOCKED,
      });
    },
  });

  const res = await request(app)
    .post(`/api/v1/driver/urgent-calls/${BOOKING_NUMBER}/lock`)
    .set('Authorization', `Bearer ${sign('DRIVER', 44)}`);

  assert.equal(res.status, 409);
  assert.equal(res.body.error_code, ERROR_CODES.URGENT_ALREADY_LOCKED);
});

test('POST /driver/urgent-calls/:bookingNumber/lock requires driver auth', async () => {
  registerUrgentNegotiationService({});

  const res = await request(app)
    .post(`/api/v1/driver/urgent-calls/${BOOKING_NUMBER}/lock`);

  assert.equal(res.status, 401);
  assert.equal(res.body.error_code, ERROR_CODES.UNAUTHORIZED);
});

test('POST /driver/urgent-calls/:bookingNumber/eta returns 200 with negotiation payload', async () => {
  let capturedUserId = null;
  let capturedBookingNumber = null;
  let capturedEtaMinutes = null;

  registerUrgentNegotiationService({
    async submitEta(driverUserId, bookingNumber, etaMinutes) {
      capturedUserId = driverUserId;
      capturedBookingNumber = bookingNumber;
      capturedEtaMinutes = etaMinutes;
      return {
        bookingNumber,
        bookingId: 10,
        negotiationId: 100,
        attemptNumber: 1,
        driverId: 7,
        status: 'AWAITING_CUSTOMER',
        etaMinutes,
        customerDecisionExpiresAt: '2099-07-23 01:32:00.000',
      };
    },
  });

  const res = await request(app)
    .post(`/api/v1/driver/urgent-calls/${BOOKING_NUMBER}/eta`)
    .set('Authorization', `Bearer ${sign('DRIVER', 44)}`)
    .send({ etaMinutes: 25 });

  assert.equal(res.status, 200);
  assert.equal(res.body.success, true);
  assert.equal(capturedUserId, 44);
  assert.equal(capturedBookingNumber, BOOKING_NUMBER);
  assert.equal(capturedEtaMinutes, 25);
  assert.equal(res.body.data.status, 'AWAITING_CUSTOMER');
  assert.equal(res.body.data.etaMinutes, 25);
});

test('POST /driver/urgent-calls/:bookingNumber/eta returns 409 when negotiation is not locked', async () => {
  registerUrgentNegotiationService({
    async submitEta() {
      throw new AppError('Urgent negotiation is not locked for ETA submission', {
        statusCode: HTTP_STATUS.CONFLICT,
        errorCode: ERROR_CODES.URGENT_NOT_LOCKED,
      });
    },
  });

  const res = await request(app)
    .post(`/api/v1/driver/urgent-calls/${BOOKING_NUMBER}/eta`)
    .set('Authorization', `Bearer ${sign('DRIVER', 44)}`)
    .send({ etaMinutes: 25 });

  assert.equal(res.status, 409);
  assert.equal(res.body.error_code, ERROR_CODES.URGENT_NOT_LOCKED);
});

test('POST /driver/urgent-calls/:bookingNumber/eta returns 403 for non-locked driver', async () => {
  registerUrgentNegotiationService({
    async submitEta() {
      throw new AppError('Only the locked driver can submit ETA', {
        statusCode: HTTP_STATUS.FORBIDDEN,
        errorCode: ERROR_CODES.URGENT_NOT_LOCKED_DRIVER,
      });
    },
  });

  const res = await request(app)
    .post(`/api/v1/driver/urgent-calls/${BOOKING_NUMBER}/eta`)
    .set('Authorization', `Bearer ${sign('DRIVER', 44)}`)
    .send({ etaMinutes: 25 });

  assert.equal(res.status, 403);
  assert.equal(res.body.error_code, ERROR_CODES.URGENT_NOT_LOCKED_DRIVER);
});

test('POST /driver/urgent-calls/:bookingNumber/eta rejects missing etaMinutes with 400', async () => {
  registerUrgentNegotiationService({
    async submitEta() {
      throw new Error('submitEta should not be called when body validation fails');
    },
  });

  const res = await request(app)
    .post(`/api/v1/driver/urgent-calls/${BOOKING_NUMBER}/eta`)
    .set('Authorization', `Bearer ${sign('DRIVER', 44)}`)
    .send({});

  assert.equal(res.status, 400);
  assert.equal(res.body.error_code, ERROR_CODES.VALIDATION_ERROR);
});

test('POST /driver/urgent-calls/:bookingNumber/eta rejects string etaMinutes with 400', async () => {
  registerUrgentNegotiationService({
    async submitEta() {
      throw new Error('submitEta should not be called when body validation fails');
    },
  });

  const res = await request(app)
    .post(`/api/v1/driver/urgent-calls/${BOOKING_NUMBER}/eta`)
    .set('Authorization', `Bearer ${sign('DRIVER', 44)}`)
    .send({ etaMinutes: '25' });

  assert.equal(res.status, 400);
  assert.equal(res.body.error_code, ERROR_CODES.VALIDATION_ERROR);
});

test('POST /driver/urgent-calls/:bookingNumber/eta requires driver auth', async () => {
  registerUrgentNegotiationService({});

  const res = await request(app)
    .post(`/api/v1/driver/urgent-calls/${BOOKING_NUMBER}/eta`)
    .send({ etaMinutes: 25 });

  assert.equal(res.status, 401);
  assert.equal(res.body.error_code, ERROR_CODES.UNAUTHORIZED);
});
