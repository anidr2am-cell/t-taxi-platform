process.env.NODE_ENV = process.env.NODE_ENV || 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'tride_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret';

const test = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');

const ERROR_CODES = require('../src/constants/errorCodes');
const config = require('../src/config');
const app = require('../src/app');

test('POST /api/v1/bookings requires Idempotency-Key in staging', async () => {
  const previousNodeEnv = config.server.nodeEnv;
  config.server.nodeEnv = 'staging';
  try {
    const response = await request(app)
      .post('/api/v1/bookings')
      .send({
        serviceTypeCode: 'AIRPORT_PICKUP',
        vehicleTypeCode: 'SUV',
        vehicleCount: 1,
        scheduledPickupAt: '2099-01-01T03:30:00.000Z',
        origin: { address: 'BKK' },
        destination: { address: 'Hotel' },
        passengers: { adults: 1, children: 0, infants: 0 },
        luggage: {
          carriers20Inch: 0,
          carriers24InchPlus: 0,
          golfBags: 0,
        },
        customer: {
          name: 'Test Customer',
          phone: '+66812345678',
          email: 'test@example.com',
        },
      });

    assert.equal(response.status, 400);
    assert.equal(response.body.error_code, ERROR_CODES.IDEMPOTENCY_KEY_REQUIRED);
  } finally {
    config.server.nodeEnv = previousNodeEnv;
  }
});

test('POST /api/v1/bookings allows missing Idempotency-Key in test env', async () => {
  assert.equal(config.server.nodeEnv, 'test');
  const response = await request(app)
    .post('/api/v1/bookings')
    .send({});
  assert.notEqual(response.body.error_code, ERROR_CODES.IDEMPOTENCY_KEY_REQUIRED);
});
