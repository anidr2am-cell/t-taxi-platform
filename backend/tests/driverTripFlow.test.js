const { test } = require('node:test');
const assert = require('node:assert/strict');
const jwt = require('jsonwebtoken');
const request = require('supertest');

process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const DriverTripFlowService = require('../src/services/driverTripFlow.service');
const DriverJobService = require('../src/services/driverJob.service');
const BookingStatusService = require('../src/services/bookingStatus.service');
const ERROR_CODES = require('../src/constants/errorCodes');
const BOOKING_STATUS = require('../src/constants/reservationStatus');
const container = require('../src/helpers/container');
const app = require('../src/app');

function sign(role = 'DRIVER', id = 44) {
  return jwt.sign(
    { sub: id, email: `${role.toLowerCase()}@example.com`, role, type: 'access' },
    process.env.JWT_ACCESS_SECRET,
    { expiresIn: '1h' },
  );
}

function detailRow(status) {
  return {
    booking_number: 'TX202607010001',
    status,
    pickup_date: '2026-07-01',
    pickup_time: '09:30',
    origin_address: 'BKK Airport',
    destination_address: 'Pattaya Hotel',
    customer_name: 'Kim',
    customer_phone: '+66123456789',
    special_requests: null,
    payment_method: 'PAY_DRIVER',
    service_type_code: 'AIRPORT_PICKUP',
    service_type_name: 'Airport Pickup',
    vehicle_type_code: 'SUV',
    vehicle_type_name: 'SUV',
    adults: 2,
    children: 0,
    infants: 0,
    carriers_20_inch: 1,
    carriers_24_inch_plus: 1,
    golf_bags: 0,
    special_items: null,
    flight_number: null,
    flight_estimated_arrival_at_text: null,
    delay_status: null,
    delay_minutes: null,
  };
}

function buildHarness(options = {}) {
  const calls = {
    transitions: [],
    emitted: 0,
  };
  const conn = {
    async beginTransaction() {},
    async commit() {
      if (options.commitError) throw options.commitError;
    },
    async rollback() {},
    release() {},
  };
  const pool = { async getConnection() { return conn; } };
  const lockedRow = options.lockedRow === undefined
    ? { booking_number: 'TX202607010001', status: options.fromStatus ?? BOOKING_STATUS.DRIVER_ASSIGNED }
    : options.lockedRow;
  const repo = {
    async findActiveDriverBookingByNumberForUpdate() {
      return lockedRow;
    },
  };
  const statusService = new BookingStatusService(pool, {}, null, null);
  statusService.transitionInTransaction = async (_conn, bookingNumber, input) => {
    calls.transitions.push(input.status);
    if (options.transitionError) throw options.transitionError;
    const fromStatus = lockedRow?.status ?? BOOKING_STATUS.DRIVER_ASSIGNED;
    return {
      result: {
        id: 7,
        bookingNumber,
        status: input.status,
        idempotent: fromStatus === input.status,
      },
      domainEvent: input.status === BOOKING_STATUS.COMPLETED ? 'trip.completed' : null,
      eventPayload: {},
      outboxId: null,
    };
  };
  statusService.dispatchOutboxAfterCommit = async () => {};
  statusService.emitDomainEvent = () => { calls.emitted += 1; };

  const jobService = new DriverJobService({
    async findActiveDriverBookingByNumber() {
      return detailRow(options.detailStatus ?? BOOKING_STATUS.DRIVER_ASSIGNED);
    },
  });

  const service = new DriverTripFlowService(pool, repo, statusService, jobService);
  return { service, calls };
}

test('DRIVER_ASSIGNED -> ON_ROUTE -> DRIVER_ARRIVED -> PICKED_UP -> SETTLEMENT_PENDING flow', async () => {
  const startHarness = buildHarness({
    fromStatus: BOOKING_STATUS.DRIVER_ASSIGNED,
    detailStatus: BOOKING_STATUS.ON_ROUTE,
  });
  const started = await startHarness.service.startOnRoute(44, 'TX202607010001');
  assert.equal(started.status, BOOKING_STATUS.ON_ROUTE);
  assert.deepEqual(startHarness.calls.transitions, [BOOKING_STATUS.ON_ROUTE]);

  const arriveHarness = buildHarness({
    fromStatus: BOOKING_STATUS.ON_ROUTE,
    detailStatus: BOOKING_STATUS.DRIVER_ARRIVED,
  });
  const arrived = await arriveHarness.service.markArrived(44, 'TX202607010001');
  assert.equal(arrived.status, BOOKING_STATUS.DRIVER_ARRIVED);

  const pickedUpHarness = buildHarness({
    fromStatus: BOOKING_STATUS.DRIVER_ARRIVED,
    detailStatus: BOOKING_STATUS.PICKED_UP,
  });
  const pickedUp = await pickedUpHarness.service.markPickedUp(44, 'TX202607010001');
  assert.equal(pickedUp.status, BOOKING_STATUS.PICKED_UP);

  const endHarness = buildHarness({
    fromStatus: BOOKING_STATUS.PICKED_UP,
    detailStatus: BOOKING_STATUS.SETTLEMENT_PENDING,
  });
  const ended = await endHarness.service.endTrip(44, 'TX202607010001');
  assert.equal(ended.status, BOOKING_STATUS.SETTLEMENT_PENDING);
});

test('endTrip returns summary when active driver job is no longer listed', async () => {
  const { service } = buildHarness({
    fromStatus: BOOKING_STATUS.PICKED_UP,
    detailStatus: BOOKING_STATUS.SETTLEMENT_PENDING,
  });
  service.driverJobService.getDetail = async () => {
    throw Object.assign(new Error('Booking not found'), {
      statusCode: 404,
      errorCode: ERROR_CODES.BOOKING_NOT_FOUND,
    });
  };

  const ended = await service.endTrip(44, 'TX202607010001');
  assert.equal(ended.status, BOOKING_STATUS.SETTLEMENT_PENDING);
  assert.equal(ended.bookingNumber, 'TX202607010001');
});

test('markArrived rejects DRIVER_ASSIGNED without ON_ROUTE', async () => {
  const { service } = buildHarness({
    fromStatus: BOOKING_STATUS.DRIVER_ASSIGNED,
    transitionError: Object.assign(new Error('Invalid booking status transition'), {
      errorCode: ERROR_CODES.INVALID_STATUS_TRANSITION,
    }),
  });

  await assert.rejects(
    () => service.markArrived(44, 'TX202607010001'),
    (err) => err.errorCode === ERROR_CODES.INVALID_STATUS_TRANSITION,
  );
});

test('repeated arrive request is rejected as stale driver state', async () => {
  const { service, calls } = buildHarness({
    fromStatus: BOOKING_STATUS.DRIVER_ARRIVED,
    detailStatus: BOOKING_STATUS.DRIVER_ARRIVED,
  });

  await assert.rejects(
    () => service.markArrived(44, 'TX202607010001'),
    (err) => err.errorCode === ERROR_CODES.INVALID_STATUS_TRANSITION,
  );
  assert.equal(calls.transitions.length, 0);
});

test('wrong role is rejected before driver trip controller', async () => {
  container.register('driverTripFlowService', () => ({
    async markArrived() {
      throw new Error('should not be called');
    },
  }));

  const res = await request(app)
    .post('/api/v1/driver/bookings/TX202607010001/arrive')
    .set('Authorization', `Bearer ${sign('CUSTOMER', 55)}`);

  assert.equal(res.status, 403);
  assert.equal(res.body.error_code, ERROR_CODES.FORBIDDEN);
});

test('other-driver booking is hidden', async () => {
  const { service } = buildHarness({ lockedRow: null });

  await assert.rejects(
    () => service.startOnRoute(44, 'TX202607010001'),
    (err) => err.errorCode === ERROR_CODES.BOOKING_NOT_FOUND,
  );
});
