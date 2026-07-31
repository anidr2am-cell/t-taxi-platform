process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET =
  process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET =
  process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const jwt = require('jsonwebtoken');
const request = require('supertest');

const app = require('../src/app');
const container = require('../src/helpers/container');
const AdminDispatchService = require('../src/services/adminDispatch.service');
const BookingStatusService = require('../src/services/bookingStatus.service');
const BookingRepository = require('../src/repositories/booking.repository');
const BOOKING_STATUS = require('../src/constants/reservationStatus');
const ERROR_CODES = require('../src/constants/errorCodes');
const ROLES = require('../src/constants/roles');
const { EVENTS } = require('../src/events');

function sign(role = 'ADMIN', id = 1) {
  return jwt.sign(
    { sub: id, email: `${role.toLowerCase()}@example.com`, role, type: 'access' },
    process.env.JWT_ACCESS_SECRET,
    { expiresIn: '1h',
    },
  );
}

function createConn() {
  return {
    began: false,
    committed: false,
    rolledBack: false,
    released: false,
    async beginTransaction() {
      this.began = true;
    },
    async commit() {
      this.committed = true;
    },
    async rollback() {
      this.rolledBack = true;
    },
    release() {
      this.released = true;
    },
  };
}

function bookingRow(overrides = {}) {
  return {
    id: 10,
    booking_number: 'TX202607010001',
    status: BOOKING_STATUS.OPEN,
    driver_id: 7,
    driver_user_id: 99,
    payment_status: 'UNPAID',
    payment_method: 'PAY_DRIVER',
    total_amount: 1200,
    currency: 'THB',
    ...overrides,
  };
}

function createProcessNoShowHarness(overrides = {}) {
  const conn = createConn();
  const pool = { async getConnection() { return conn; } };
  const calls = {
    transitions: [],
    clearAssignment: [],
    penalties: [],
    dispatchOutboxIds: [],
  };

  const booking = bookingRow(overrides.booking);
  const bookingRepository = {
    async findByBookingNumberForUpdate() {
      return overrides.booking === false ? null : booking;
    },
    async clearAssignmentOnCancel(_conn, bookingId, actorUserId, reason) {
      calls.clearAssignment.push({ bookingId, actorUserId, reason });
      return overrides.activeAssignment ?? { id: 77, driver_id: 7 };
    },
  };

  const penaltyRepository = {
    async findByBookingId(bookingId) {
      if (overrides.existingPenalty) {
        return {
          id: 1,
          booking_id: bookingId,
          penalty_amount: 500,
          currency: 'THB',
          reason: 'Existing',
          created_by_admin_id: 1,
          created_at: '2026-07-01 10:00:00',
        };
      }
      return null;
    },
    async insert(_conn, row) {
      calls.penalties.push(row);
      return {
        id: 2,
        booking_id: row.bookingId,
        penalty_amount: row.penaltyAmount,
        currency: row.currency,
        reason: row.reason,
        created_by_admin_id: row.createdByAdminId,
        created_at: '2026-07-01 11:00:00',
      };
    },
  };

  const bookingStatusService = {
    async transitionInTransaction(_conn, bookingNumber, input, actor, options) {
      calls.transitions.push({ bookingNumber, input, actor, options });
      if (overrides.transitionError) {
        throw overrides.transitionError;
      }
      return {
        result: {
          bookingNumber,
          status: input.status,
          idempotent: false,
        },
        domainEvent: EVENTS.BOOKING_NO_SHOW,
        eventPayload: { bookingNumber },
        outboxId: 501,
        releasedDriverUserId: null,
      };
    },
    async dispatchOutboxAfterCommit(outboxId) {
      calls.dispatchOutboxIds.push(outboxId);
    },
  };

  const service = new AdminDispatchService(
    pool,
    bookingRepository,
    {},
    bookingStatusService,
    {},
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    penaltyRepository,
  );

  return { service, conn, calls, booking };
}

test('processNoShow marks booking, clears assignment, and stores penalty', async () => {
  const { service, conn, calls } = createProcessNoShowHarness({
    booking: { status: BOOKING_STATUS.DRIVER_ASSIGNED },
  });

  const result = await service.processNoShow(
    'TX202607010001',
    { penaltyAmount: 500, reason: 'Customer did not show up', memo: 'Confirmed by phone' },
    { id: 1, role: ROLES.ADMIN },
  );

  assert.equal(conn.committed, true);
  assert.equal(calls.transitions.length, 1);
  assert.equal(calls.transitions[0].input.status, BOOKING_STATUS.NO_SHOW);
  assert.equal(calls.transitions[0].input.reason, 'Customer did not show up');
  assert.equal(calls.transitions[0].input.memo, 'Confirmed by phone');
  assert.deepEqual(calls.clearAssignment[0], {
    bookingId: 10,
    actorUserId: 1,
    reason: 'ADMIN_NO_SHOW',
  });
  assert.equal(calls.penalties[0].penaltyAmount, 500);
  assert.equal(calls.penalties[0].reason, 'Customer did not show up');
  assert.deepEqual(calls.dispatchOutboxIds, [501]);
  assert.equal(result.status, BOOKING_STATUS.NO_SHOW);
  assert.equal(result.noShowPenalty.amount, 500);
  assert.equal(result.noShowPenalty.reason, 'Customer did not show up');
});

test('processNoShow rejects invalid status transitions such as PICKED_UP', async () => {
  const transitionError = new (require('../src/utils/AppError'))(
    'Invalid booking status transition from PICKED_UP to NO_SHOW',
    {
      statusCode: 409,
      errorCode: ERROR_CODES.INVALID_STATUS_TRANSITION,
    },
  );

  const { service, conn, calls } = createProcessNoShowHarness({
    booking: { status: BOOKING_STATUS.PICKED_UP },
    transitionError,
  });

  await assert.rejects(
    () => service.processNoShow(
      'TX202607010001',
      { penaltyAmount: 500, reason: 'Too late' },
      { id: 1, role: ROLES.ADMIN },
    ),
    (err) => err.errorCode === ERROR_CODES.INVALID_STATUS_TRANSITION,
  );

  assert.equal(conn.rolledBack, true);
  assert.equal(calls.penalties.length, 0);
  assert.equal(calls.clearAssignment.length, 0);
});

test('processNoShow rejects duplicate processing when penalty already exists', async () => {
  const { service, conn, calls } = createProcessNoShowHarness({
    existingPenalty: true,
  });

  await assert.rejects(
    () => service.processNoShow(
      'TX202607010001',
      { penaltyAmount: 500, reason: 'Duplicate attempt' },
      { id: 1, role: ROLES.ADMIN },
    ),
    (err) => err.errorCode === ERROR_CODES.BOOKING_NO_SHOW_ALREADY_PROCESSED,
  );

  assert.equal(conn.rolledBack, true);
  assert.equal(calls.transitions.length, 0);
});

test('booking status service keeps NO_SHOW unavailable after PICKED_UP', () => {
  const bookingStatusService = new BookingStatusService({}, new BookingRepository(), null, null);

  assert.throws(
    () => bookingStatusService.validateTransition(
      BOOKING_STATUS.PICKED_UP,
      BOOKING_STATUS.NO_SHOW,
      ROLES.ADMIN,
    ),
    (err) => err.errorCode === ERROR_CODES.INVALID_STATUS_TRANSITION,
  );
});

test('POST /admin/bookings/:bookingNumber/no-show requires admin role', async () => {
  const resDriver = await request(app)
    .post('/api/v1/admin/bookings/TX202607010001/no-show')
    .set('Authorization', `Bearer ${sign('DRIVER')}`)
    .send({ penaltyAmount: 500, reason: 'No show' });

  assert.equal(resDriver.status, 403);

  const resCustomer = await request(app)
    .post('/api/v1/admin/bookings/TX202607010001/no-show')
    .set('Authorization', `Bearer ${sign('CUSTOMER')}`)
    .send({ penaltyAmount: 500, reason: 'No show' });

  assert.equal(resCustomer.status, 403);
});

test('POST /admin/bookings/:bookingNumber/no-show succeeds for ADMIN', async () => {
  container.register('adminDispatchService', () => ({
    async processNoShow(bookingNumber, body) {
      return {
        bookingNumber,
        status: BOOKING_STATUS.NO_SHOW,
        noShowPenalty: {
          amount: body.penaltyAmount,
          currency: 'THB',
          reason: body.reason,
          createdByAdminId: 1,
          createdAt: '2026-07-01T11:00:00.000Z',
        },
      };
    },
  }));

  const res = await request(app)
    .post('/api/v1/admin/bookings/TX202607010001/no-show')
    .set('Authorization', `Bearer ${sign('ADMIN')}`)
    .send({ penaltyAmount: 500, reason: 'Customer no-show confirmed' });

  assert.equal(res.status, 200);
  assert.equal(res.body.data.status, BOOKING_STATUS.NO_SHOW);
  assert.equal(res.body.data.noShowPenalty.amount, 500);
});

test('POST /admin/bookings/:bookingNumber/no-show validates request body', async () => {
  const res = await request(app)
    .post('/api/v1/admin/bookings/TX202607010001/no-show')
    .set('Authorization', `Bearer ${sign('ADMIN')}`)
    .send({ penaltyAmount: 0, reason: '' });

  assert.equal(res.status, 400);
  assert.equal(res.body.error_code, ERROR_CODES.VALIDATION_ERROR);
});

test('booking detail includes noShowPenalty when present', async () => {
  const bookingRepo = {
    async findAdminBookingDetail() {
      return {
        id: 1,
        booking_number: 'TX202607010001',
        status: BOOKING_STATUS.NO_SHOW,
        scheduled_pickup_at: '2026-07-01 09:30:00',
        origin_address: 'BKK',
        destination_address: 'Pattaya',
        customer_name: 'Kim',
        customer_email: 'kim@example.com',
        customer_phone: '+66123456789',
        customer_country_code: 'TH',
        special_requests: null,
        payment_method: 'PAY_DRIVER',
        payment_status: 'UNPAID',
        commission_status: 'NOT_DUE_YET',
        total_amount: 1200,
        currency: 'THB',
        vehicle_count: 1,
        created_at: '2026-06-30 10:00:00',
        updated_at: '2026-06-30 10:00:00',
        metadata: null,
        service_type_code: 'AIRPORT_PICKUP',
        service_type_name: 'Airport Pickup',
        vehicle_type_code: 'SUV',
        vehicle_type_name: 'SUV',
        adults: 2,
        children: 0,
        infants: 0,
        carriers_20_inch: 1,
        carriers_24_inch_plus: 0,
        golf_bags: 0,
        special_items: null,
        flight_number: 'TG409',
        flight_scheduled_arrival_at: null,
        flight_estimated_arrival_at: null,
        delay_status: null,
        delay_minutes: null,
        airport_code_custom: 'BKK',
        airport_iata: 'BKK',
      };
    },
    async findChargeItemsByBookingId() {
      return [];
    },
    async findStatusLogsByBookingId() {
      return [];
    },
    async findAssignmentsByBookingId() {
      return [];
    },
  };

  const penaltyRepository = {
    async findByBookingId(bookingId) {
      assert.equal(bookingId, 1);
      return {
        penalty_amount: 500,
        currency: 'THB',
        reason: 'Customer no-show',
        created_by_admin_id: 1,
        created_at: '2026-07-01 11:00:00',
      };
    },
  };

  const service = new AdminDispatchService(
    {},
    bookingRepo,
    {},
    {},
    { async driverHasBlockingSettlement() { return false; } },
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    penaltyRepository,
  );

  const detail = await service.getBookingDetail('TX202607010001');
  assert.equal(detail.noShowPenalty.amount, 500);
  assert.equal(detail.noShowPenalty.reason, 'Customer no-show');
});

test('booking detail returns null noShowPenalty when absent', async () => {
  const bookingRepo = {
    async findAdminBookingDetail() {
      return {
        id: 1,
        booking_number: 'TX202607010001',
        status: BOOKING_STATUS.OPEN,
        scheduled_pickup_at: '2026-07-01 09:30:00',
        origin_address: 'BKK',
        destination_address: 'Pattaya',
        customer_name: 'Kim',
        customer_email: 'kim@example.com',
        customer_phone: '+66123456789',
        customer_country_code: 'TH',
        special_requests: null,
        payment_method: 'PAY_DRIVER',
        payment_status: 'UNPAID',
        commission_status: 'NOT_DUE_YET',
        total_amount: 1200,
        currency: 'THB',
        vehicle_count: 1,
        created_at: '2026-06-30 10:00:00',
        updated_at: '2026-06-30 10:00:00',
        metadata: null,
        service_type_code: 'AIRPORT_PICKUP',
        service_type_name: 'Airport Pickup',
        vehicle_type_code: 'SUV',
        vehicle_type_name: 'SUV',
        adults: 2,
        children: 0,
        infants: 0,
        carriers_20_inch: 1,
        carriers_24_inch_plus: 0,
        golf_bags: 0,
        special_items: null,
        flight_number: 'TG409',
        flight_scheduled_arrival_at: null,
        flight_estimated_arrival_at: null,
        delay_status: null,
        delay_minutes: null,
        airport_code_custom: 'BKK',
        airport_iata: 'BKK',
      };
    },
    async findChargeItemsByBookingId() {
      return [];
    },
    async findStatusLogsByBookingId() {
      return [];
    },
    async findAssignmentsByBookingId() {
      return [];
    },
  };

  const penaltyRepository = {
    async findByBookingId() {
      return null;
    },
  };

  const service = new AdminDispatchService(
    {},
    bookingRepo,
    {},
    {},
    { async driverHasBlockingSettlement() { return false; } },
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    penaltyRepository,
  );

  const detail = await service.getBookingDetail('TX202607010001');
  assert.equal(detail.noShowPenalty, null);
});
