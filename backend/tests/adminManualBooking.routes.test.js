process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'tride_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret';
process.env.SOCIAL_TOKEN_ENCRYPTION_KEY = process.env.SOCIAL_TOKEN_ENCRYPTION_KEY
  || Buffer.alloc(32, 1).toString('base64');

const { test } = require('node:test');
const assert = require('node:assert/strict');
const jwt = require('jsonwebtoken');
const request = require('supertest');
const ERROR_CODES = require('../src/constants/errorCodes');
const container = require('../src/helpers/container');
const app = require('../src/app');

function sign(role = 'ADMIN', id = 1) {
  return jwt.sign(
    { sub: id, id, email: 'admin@example.com', role, type: 'access' },
    process.env.JWT_ACCESS_SECRET,
    { expiresIn: '1h' },
  );
}

test('PATCH /admin/bookings/:bookingNumber/manual accepts memo-only body through validator', async () => {
  let capturedBody = null;
  container.register('bookingService', () => ({
    async updateAdminManualBooking(_bookingNumber, body) {
      capturedBody = body;
      return {
        bookingNumber: 'TX202607130001',
        status: 'OPEN',
        payoutAmount: 800,
      };
    },
  }));

  const res = await request(app)
    .patch('/api/v1/admin/bookings/TX202607130001/manual')
    .set('Authorization', `Bearer ${sign('ADMIN')}`)
    .send({ memo: 'validator path memo only' });

  assert.equal(res.status, 200);
  assert.deepEqual(capturedBody, { memo: 'validator path memo only' });
});

test('PATCH /admin/bookings/:bookingNumber/manual rejects memo-only body with invalid payoutAmount', async () => {
  const res = await request(app)
    .patch('/api/v1/admin/bookings/TX202607130001/manual')
    .set('Authorization', `Bearer ${sign('ADMIN')}`)
    .send({ memo: 'bad payout', payoutAmount: -1 });

  assert.equal(res.status, 400);
  assert.equal(res.body.error_code, ERROR_CODES.VALIDATION_ERROR);
});
