process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';
process.env.SOCIAL_TOKEN_ENCRYPTION_KEY =
  process.env.SOCIAL_TOKEN_ENCRYPTION_KEY || Buffer.alloc(32, 1).toString('base64');

const { test } = require('node:test');
const assert = require('node:assert/strict');
const jwt = require('jsonwebtoken');
const request = require('supertest');

const app = require('../src/app');
const container = require('../src/helpers/container');
const BOOKING_STATUS = require('../src/constants/reservationStatus');
const AdminDispatchService = require('../src/services/adminDispatch.service');

function createService(bookingStatusService = {}) {
  return new AdminDispatchService(
    {},
    {},
    {},
    bookingStatusService,
    {},
    {},
    {},
    {},
  );
}

function sign(role = 'ADMIN', id = 9) {
  return jwt.sign(
    { sub: id, email: 'admin@example.com', role, type: 'access' },
    process.env.JWT_ACCESS_SECRET,
    { expiresIn: '1h' },
  );
}

test('booking detail action allows admin completion for every actively assigned trip status', () => {
  const service = createService();
  const activeAssignment = { id: 44 };

  for (const status of [
    BOOKING_STATUS.DRIVER_ASSIGNED,
    BOOKING_STATUS.ON_ROUTE,
    BOOKING_STATUS.DRIVER_ARRIVED,
    BOOKING_STATUS.PICKED_UP,
  ]) {
    assert.ok(
      service.computeAllowedActions({ status }, activeAssignment).includes(
        'COMPLETE_TRIP',
      ),
      status,
    );
  }
  assert.ok(
    !service.computeAllowedActions(
      { status: BOOKING_STATUS.PICKED_UP },
      null,
    ).includes('COMPLETE_TRIP'),
  );
  assert.ok(
    !service.computeAllowedActions(
      { status: BOOKING_STATUS.SETTLEMENT_PENDING },
      activeAssignment,
    ).includes('COMPLETE_TRIP'),
  );
});

test('completeActiveTrip reuses the booking state machine and moves the trip to settlement pending', async () => {
  let captured;
  const service = createService({
    async transition(bookingNumber, input, actor, options) {
      captured = { bookingNumber, input, actor, options };
      return { bookingNumber, status: input.status };
    },
  });

  const result = await service.completeActiveTrip(
    'TX202609260001',
    { id: 9, role: 'ADMIN' },
  );

  assert.deepEqual(captured, {
    bookingNumber: 'TX202609260001',
    input: {
      status: BOOKING_STATUS.SETTLEMENT_PENDING,
      reason: 'ADMIN_COMPLETE_TRIP',
    },
    actor: { id: 9, role: 'ADMIN' },
    options: {
      allowAdminCompleteActiveTrip: true,
      requireActiveAssignment: true,
    },
  });
  assert.equal(result.status, BOOKING_STATUS.SETTLEMENT_PENDING);
});

test('admin complete-trip endpoint delegates to the admin dispatch service', async () => {
  let captured;
  container.register('adminDispatchService', () => ({
    async completeActiveTrip(bookingNumber, user) {
      captured = { bookingNumber, userId: user.id, role: user.role };
      return { bookingNumber, status: BOOKING_STATUS.SETTLEMENT_PENDING };
    },
  }));

  const response = await request(app)
    .post('/api/v1/admin/bookings/TX202609260001/complete-trip')
    .set('Authorization', `Bearer ${sign()}`)
    .send({});

  assert.equal(response.status, 200);
  assert.equal(response.body.data.status, BOOKING_STATUS.SETTLEMENT_PENDING);
  assert.deepEqual(captured, {
    bookingNumber: 'TX202609260001',
    userId: 9,
    role: 'ADMIN',
  });
});
