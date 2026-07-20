process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const test = require('node:test');
const assert = require('node:assert/strict');
const jwt = require('jsonwebtoken');
const request = require('supertest');
const app = require('../src/app');
const DriverJobService = require('../src/services/driverJob.service');
const BOOKING_STATUS = require('../src/constants/reservationStatus');

function sign(role = 'DRIVER', id = 44) {
  return jwt.sign(
    { sub: id, email: `${role.toLowerCase()}@example.com`, role, type: 'access' },
    process.env.JWT_ACCESS_SECRET,
    { expiresIn: '1h' },
  );
}

test('driver allowed actions expose button flow without QR actions', () => {
  const service = new DriverJobService({});
  assert.deepEqual(service.allowedActions({
    status: BOOKING_STATUS.DRIVER_ASSIGNED,
    assignment_status: 'ASSIGNED',
    scheduled_pickup_at: '2026-07-18 22:00:00',
  }, new Date('2026-07-18T13:59:59.000Z')), [
    'VIEW_DETAILS',
  ]);
  assert.deepEqual(service.allowedActions({
    status: BOOKING_STATUS.DRIVER_ASSIGNED,
    assignment_status: 'ASSIGNED',
    scheduled_pickup_at: '2026-07-18 22:00:00',
  }, new Date('2026-07-18T15:00:00.000Z')), [
    'VIEW_DETAILS',
    'ACCEPT_BOOKING',
  ]);
  assert.deepEqual(service.allowedActions({
    status: BOOKING_STATUS.DRIVER_ASSIGNED,
    assignment_status: 'ACCEPTED',
  }), [
    'VIEW_DETAILS',
    'START_ON_ROUTE',
  ]);
  assert.deepEqual(service.allowedActions({ status: BOOKING_STATUS.ON_ROUTE }), [
    'VIEW_DETAILS',
    'MARK_ARRIVED',
  ]);
  assert.deepEqual(service.allowedActions({ status: BOOKING_STATUS.DRIVER_ARRIVED }), [
    'VIEW_DETAILS',
    'MARK_PICKED_UP',
  ]);
  assert.deepEqual(service.allowedActions({ status: BOOKING_STATUS.PICKED_UP }), [
    'VIEW_DETAILS',
    'END_TRIP',
  ]);
  assert.deepEqual(service.allowedActions({ status: BOOKING_STATUS.SETTLEMENT_PENDING }), []);
});

test('mark-picked-up route requires driver role', async () => {
  const res = await request(app)
    .post('/api/v1/driver/bookings/TX202607010001/mark-picked-up')
    .set('Authorization', `Bearer ${sign('CUSTOMER', 55)}`);

  assert.equal(res.status, 403);
});

test('end-trip route requires driver role', async () => {
  const res = await request(app)
    .post('/api/v1/driver/bookings/TX202607010001/end-trip')
    .set('Authorization', `Bearer ${sign('CUSTOMER', 55)}`);

  assert.equal(res.status, 403);
});

test('release route requires driver role', async () => {
  const res = await request(app)
    .post('/api/v1/driver/bookings/TX202607010001/release')
    .set('Authorization', `Bearer ${sign('CUSTOMER', 55)}`);

  assert.equal(res.status, 403);
});
