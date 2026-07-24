const { test } = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const jwt = require('jsonwebtoken');
const request = require('supertest');

process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const ERROR_CODES = require('../src/constants/errorCodes');
const container = require('../src/helpers/container');
const app = require('../src/app');

const VALID_BOOKING_NUMBER = 'TX202607010001';

function sign(role = 'DRIVER', id = 44) {
  return jwt.sign(
    { sub: id, email: `${role.toLowerCase()}@example.com`, role, type: 'access' },
    process.env.JWT_ACCESS_SECRET,
    { expiresIn: '1h' },
  );
}

test('driver.routes declares static booking list routes before dynamic booking detail route', () => {
  const source = readFileSync(join(__dirname, '../src/routes/driver.routes.js'), 'utf8');
  const scheduledIndex = source.indexOf("router.get('/bookings/scheduled'");
  const todayIndex = source.indexOf("router.get('/bookings/today'");
  const detailIndex = source.indexOf("router.get('/bookings/:bookingNumber'");

  assert.ok(scheduledIndex >= 0, 'scheduled route must exist');
  assert.ok(todayIndex >= 0, 'today route must exist');
  assert.ok(detailIndex >= 0, 'booking detail route must exist');
  assert.ok(scheduledIndex < detailIndex, 'scheduled must be registered before :bookingNumber');
  assert.ok(todayIndex < detailIndex, 'today must be registered before :bookingNumber');
  assert.ok(scheduledIndex < todayIndex, 'scheduled must be registered before today');
});

test('GET /driver/bookings/scheduled does not hit booking detail validator', async () => {
  let scheduledCalled = false;
  let detailCalled = false;

  container.register('driverJobService', () => ({
    async listScheduled(driverUserId) {
      scheduledCalled = true;
      assert.equal(driverUserId, 44);
      return { date: '2026-07-01', items: [] };
    },
    async getDetail() {
      detailCalled = true;
      throw new Error('getDetail should not be called for /scheduled');
    },
  }));

  const res = await request(app)
    .get('/api/v1/driver/bookings/scheduled')
    .set('Authorization', `Bearer ${sign('DRIVER', 44)}`);

  assert.equal(res.status, 200);
  assert.equal(res.body.success, true);
  assert.equal(scheduledCalled, true);
  assert.equal(detailCalled, false);
});

test('GET /driver/bookings/today does not hit booking detail validator', async () => {
  let todayCalled = false;
  let detailCalled = false;

  container.register('driverJobService', () => ({
    async listToday(driverUserId) {
      todayCalled = true;
      assert.equal(driverUserId, 44);
      return { date: '2026-07-01', items: [] };
    },
    async getDetail() {
      detailCalled = true;
      throw new Error('getDetail should not be called for /today');
    },
  }));

  const res = await request(app)
    .get('/api/v1/driver/bookings/today')
    .set('Authorization', `Bearer ${sign('DRIVER', 44)}`);

  assert.equal(res.status, 200);
  assert.equal(res.body.success, true);
  assert.equal(todayCalled, true);
  assert.equal(detailCalled, false);
});

test('GET /driver/bookings/:bookingNumber keeps detail route behavior for valid booking number', async () => {
  let detailBookingNumber = null;

  container.register('driverJobService', () => ({
    async getDetail(driverUserId, bookingNumber) {
      assert.equal(driverUserId, 44);
      detailBookingNumber = bookingNumber;
      return {
        bookingNumber,
        status: 'DRIVER_ASSIGNED',
        assignmentStatus: 'ASSIGNED',
      };
    },
  }));

  const res = await request(app)
    .get(`/api/v1/driver/bookings/${VALID_BOOKING_NUMBER}`)
    .set('Authorization', `Bearer ${sign('DRIVER', 44)}`);

  assert.equal(res.status, 200);
  assert.equal(res.body.data.bookingNumber, VALID_BOOKING_NUMBER);
  assert.equal(detailBookingNumber, VALID_BOOKING_NUMBER);
});

test('GET /driver/bookings/invalid keeps booking number validation on dynamic detail route', async () => {
  const DriverJobService = require('../src/services/driverJob.service');
  container.register('driverJobService', () => new DriverJobService({}));

  const res = await request(app)
    .get('/api/v1/driver/bookings/invalid')
    .set('Authorization', `Bearer ${sign('DRIVER', 44)}`);

  assert.equal(res.status, 400);
  assert.equal(res.body.error_code, ERROR_CODES.VALIDATION_ERROR);
  assert.match(res.body.message, /Invalid booking number/i);
});

test('GET /driver/bookings/scheduled avoids Invalid booking number regression response', async () => {
  container.register('driverJobService', () => ({
    async listScheduled() {
      return { date: '2026-07-01', items: [] };
    },
  }));

  const res = await request(app)
    .get('/api/v1/driver/bookings/scheduled')
    .set('Authorization', `Bearer ${sign('DRIVER', 44)}`);

  assert.notEqual(res.status, 400);
  assert.notEqual(res.body.message, 'Invalid booking number');
});
