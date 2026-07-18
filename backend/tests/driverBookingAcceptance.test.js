const { test } = require('node:test');
const assert = require('node:assert/strict');
const jwt = require('jsonwebtoken');
const request = require('supertest');

process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const DriverBookingAcceptanceService = require('../src/services/driverBookingAcceptance.service');
const BookingRepository = require('../src/repositories/booking.repository');
const AppError = require('../src/utils/AppError');
const ERROR_CODES = require('../src/constants/errorCodes');
const BOOKING_STATUS = require('../src/constants/reservationStatus');
const container = require('../src/helpers/container');
const app = require('../src/app');

const BOOKING_NUMBER = 'TX202607180001';
// mysql2 parses the Bangkok DATETIME digits using the connection's +00:00
// timezone, so 22:30 is represented as a Date whose UTC digits are 22:30.
const ACCEPTED_AT = new Date('2026-07-18T22:30:00.000Z');

function sign(role = 'DRIVER', id = 44) {
  return jwt.sign(
    { sub: id, email: `${role.toLowerCase()}@example.com`, role, type: 'access' },
    process.env.JWT_ACCESS_SECRET,
    { expiresIn: '1h' },
  );
}

function createConnection() {
  return {
    began: false,
    committed: false,
    rolledBack: false,
    released: false,
    async beginTransaction() { this.began = true; },
    async commit() { this.committed = true; },
    async rollback() { this.rolledBack = true; },
    release() { this.released = true; },
  };
}

function createHarness(overrides = {}) {
  const conn = createConnection();
  const calls = { accepted: [], activities: [] };
  const driver = overrides.driver === undefined
    ? { id: 7, user_id: 44, is_active: 1, user_is_active: 1 }
    : overrides.driver;
  const booking = overrides.booking === undefined
    ? { id: 10, booking_number: BOOKING_NUMBER, status: BOOKING_STATUS.DRIVER_ASSIGNED }
    : overrides.booking;
  let assignment = overrides.assignment === undefined
    ? { id: 77, driver_id: 7, status: 'ASSIGNED', accepted_at: null }
    : overrides.assignment;

  const bookingRepository = {
    async findByBookingNumberForUpdate() { return booking; },
    async findActiveAssignmentForUpdate() { return assignment; },
    async acceptDriverAssignment(_conn, assignmentId) {
      calls.accepted.push(assignmentId);
      if (overrides.acceptError) throw overrides.acceptError;
      if (overrides.acceptResult === null) return null;
      assignment = { ...assignment, status: 'ACCEPTED', accepted_at: ACCEPTED_AT };
      return assignment;
    },
    async insertActivityLog(_conn, bookingId, activity) {
      calls.activities.push({ bookingId, activity });
    },
  };
  const driverRepository = {
    async findByUserIdForUpdate() { return driver; },
  };
  const driverJobService = {
    validateBookingNumber(value) {
      const normalized = String(value || '').trim().toUpperCase();
      if (!/^TX\d{12}$/.test(normalized)) {
        throw new AppError('Invalid booking number', {
          statusCode: 400,
          errorCode: ERROR_CODES.VALIDATION_ERROR,
        });
      }
      return normalized;
    },
  };
  const pool = { async getConnection() { return conn; } };
  return {
    conn,
    calls,
    service: new DriverBookingAcceptanceService(
      pool,
      bookingRepository,
      driverRepository,
      driverJobService,
    ),
  };
}

test('accepts own ASSIGNED assignment and keeps booking DRIVER_ASSIGNED', async () => {
  const { service, conn, calls } = createHarness();

  const result = await service.acceptBooking(44, BOOKING_NUMBER);

  assert.deepEqual(result, {
    bookingNumber: BOOKING_NUMBER,
    bookingStatus: BOOKING_STATUS.DRIVER_ASSIGNED,
    assignmentStatus: 'ACCEPTED',
    acceptedAt: '2026-07-18T15:30:00.000Z',
    idempotent: false,
  });
  assert.equal(conn.committed, true);
  assert.equal(conn.rolledBack, false);
  assert.deepEqual(calls.accepted, [77]);
  assert.equal(calls.activities.length, 1);
  assert.equal(calls.activities[0].activity.activityType, 'DRIVER_BOOKING_ACCEPTED');
  assert.equal(calls.activities[0].activity.actorUserId, 44);
});

test('repeated acceptance is idempotent and preserves accepted_at', async () => {
  const acceptedAt = '2026-07-18 21:00:00';
  const { service, calls } = createHarness({
    assignment: { id: 77, driver_id: 7, status: 'ACCEPTED', accepted_at: acceptedAt },
  });

  const result = await service.acceptBooking(44, BOOKING_NUMBER);

  assert.equal(result.idempotent, true);
  assert.equal(result.acceptedAt, '2026-07-18T14:00:00.000Z');
  assert.equal(calls.accepted.length, 0);
  assert.equal(calls.activities.length, 0);
});

test('converts mysql2 Date accepted_at from Bangkok wall clock to UTC ISO', () => {
  const { service } = createHarness();

  assert.equal(
    service.acceptedAtIso(new Date('2026-07-18T22:30:00.000Z')),
    '2026-07-18T15:30:00.000Z',
  );
});

test('converts timezone-less MySQL accepted_at from Bangkok wall clock to UTC ISO', () => {
  const { service } = createHarness();

  assert.equal(
    service.acceptedAtIso('2026-07-18 22:30:00'),
    '2026-07-18T15:30:00.000Z',
  );
  assert.equal(
    service.acceptedAtIso('2026-07-18T22:30:00'),
    '2026-07-18T15:30:00.000Z',
  );
});

test('does not shift accepted_at strings that already declare UTC or an offset', () => {
  const { service } = createHarness();

  assert.equal(
    service.acceptedAtIso('2026-07-18T15:30:00.000Z'),
    '2026-07-18T15:30:00.000Z',
  );
  assert.equal(
    service.acceptedAtIso('2026-07-18T22:30:00+07:00'),
    '2026-07-18T15:30:00.000Z',
  );
});

test('rejects missing or invalid accepted_at values', () => {
  const { service } = createHarness();

  for (const value of [null, '', 'not-a-date', new Date('invalid')]) {
    assert.throws(
      () => service.acceptedAtIso(value),
      /Accepted assignment is missing accepted_at/,
    );
  }
});

test('hides another driver assignment as BOOKING_NOT_FOUND', async () => {
  const { service, conn } = createHarness({
    assignment: { id: 77, driver_id: 99, status: 'ASSIGNED', accepted_at: null },
  });
  await assert.rejects(
    () => service.acceptBooking(44, BOOKING_NUMBER),
    (error) => error.statusCode === 404 && error.errorCode === ERROR_CODES.BOOKING_NOT_FOUND,
  );
  assert.equal(conn.rolledBack, true);
});

test('rejects missing booking or active assignment as not found', async () => {
  for (const options of [{ booking: null }, { assignment: null }]) {
    const { service } = createHarness(options);
    await assert.rejects(
      () => service.acceptBooking(44, BOOKING_NUMBER),
      (error) => error.statusCode === 404 && error.errorCode === ERROR_CODES.BOOKING_NOT_FOUND,
    );
  }
});

test('rejects cancelled or started booking as BOOKING_NOT_ACCEPTABLE', async () => {
  for (const status of [BOOKING_STATUS.CANCELLED, BOOKING_STATUS.ON_ROUTE]) {
    const { service } = createHarness({
      booking: { id: 10, booking_number: BOOKING_NUMBER, status },
    });
    await assert.rejects(
      () => service.acceptBooking(44, BOOKING_NUMBER),
      (error) => error.statusCode === 409
        && error.errorCode === ERROR_CODES.BOOKING_NOT_ACCEPTABLE,
    );
  }
});

test('rejects inactive assignment state', async () => {
  const { service } = createHarness({
    assignment: { id: 77, driver_id: 7, status: 'CANCELLED', accepted_at: null },
  });
  await assert.rejects(
    () => service.acceptBooking(44, BOOKING_NUMBER),
    (error) => error.statusCode === 409
      && error.errorCode === ERROR_CODES.BOOKING_NOT_ACCEPTABLE,
  );
});

test('rejects inactive driver with 403', async () => {
  for (const driver of [
    { id: 7, user_id: 44, is_active: 0, user_is_active: 1 },
    { id: 7, user_id: 44, is_active: 1, user_is_active: 0 },
  ]) {
    const { service } = createHarness({ driver });
    await assert.rejects(
      () => service.acceptBooking(44, BOOKING_NUMBER),
      (error) => error.statusCode === 403 && error.errorCode === ERROR_CODES.DRIVER_INACTIVE,
    );
  }
});

test('validates booking number before opening a transaction', async () => {
  const { service, conn } = createHarness();
  await assert.rejects(
    () => service.acceptBooking(44, 'invalid'),
    (error) => error.statusCode === 400 && error.errorCode === ERROR_CODES.VALIDATION_ERROR,
  );
  assert.equal(conn.began, false);
});

test('conditional update race resolves to idempotent accepted state', async () => {
  const accepted = { id: 77, driver_id: 7, status: 'ACCEPTED', accepted_at: ACCEPTED_AT };
  let reads = 0;
  const harness = createHarness({ acceptResult: null });
  harness.service.bookingRepository.findActiveAssignmentForUpdate = async () => {
    reads += 1;
    return reads === 1
      ? { id: 77, driver_id: 7, status: 'ASSIGNED', accepted_at: null }
      : accepted;
  };

  const result = await harness.service.acceptBooking(44, BOOKING_NUMBER);

  assert.equal(result.idempotent, true);
  assert.equal(result.acceptedAt, '2026-07-18T15:30:00.000Z');
  assert.equal(harness.calls.activities.length, 0);
});

test('concurrent accept requests produce one transition and one idempotent success', async () => {
  let assignment = { id: 77, driver_id: 7, status: 'ASSIGNED', accepted_at: null };
  let updateCount = 0;
  const repository = {
    async findByBookingNumberForUpdate() {
      return { id: 10, booking_number: BOOKING_NUMBER, status: BOOKING_STATUS.DRIVER_ASSIGNED };
    },
    async findActiveAssignmentForUpdate() { return { ...assignment }; },
    async acceptDriverAssignment() {
      if (assignment.status !== 'ASSIGNED') return null;
      updateCount += 1;
      assignment = { ...assignment, status: 'ACCEPTED', accepted_at: ACCEPTED_AT };
      return { ...assignment };
    },
    async insertActivityLog() {},
  };
  const driverRepository = {
    async findByUserIdForUpdate() {
      return { id: 7, user_id: 44, is_active: 1, user_is_active: 1 };
    },
  };
  const driverJobService = { validateBookingNumber: (value) => value };
  const pool = {
    async getConnection() { return createConnection(); },
  };
  const service = new DriverBookingAcceptanceService(
    pool,
    repository,
    driverRepository,
    driverJobService,
  );

  const results = await Promise.all([
    service.acceptBooking(44, BOOKING_NUMBER),
    service.acceptBooking(44, BOOKING_NUMBER),
  ]);

  assert.equal(updateCount, 1);
  assert.deepEqual(results.map((result) => result.idempotent).sort(), [false, true]);
  assert.equal(results[0].acceptedAt, results[1].acceptedAt);
});

test('accept loses safely when release or start-route wins the lock', async () => {
  const released = createHarness({ assignment: null });
  await assert.rejects(
    () => released.service.acceptBooking(44, BOOKING_NUMBER),
    (error) => error.errorCode === ERROR_CODES.BOOKING_NOT_FOUND,
  );

  const started = createHarness({
    booking: { id: 10, booking_number: BOOKING_NUMBER, status: BOOKING_STATUS.ON_ROUTE },
    assignment: { id: 77, driver_id: 7, status: 'ACCEPTED', accepted_at: ACCEPTED_AT },
  });
  await assert.rejects(
    () => started.service.acceptBooking(44, BOOKING_NUMBER),
    (error) => error.errorCode === ERROR_CODES.BOOKING_NOT_ACCEPTABLE,
  );
});

test('transaction rolls back when assignment update fails', async () => {
  const { service, conn, calls } = createHarness({ acceptError: new Error('update failed') });
  await assert.rejects(() => service.acceptBooking(44, BOOKING_NUMBER), /update failed/);
  assert.equal(conn.committed, false);
  assert.equal(conn.rolledBack, true);
  assert.equal(conn.released, true);
  assert.equal(calls.activities.length, 0);
});

test('repository acceptance uses conditional update and preserves timestamp', async () => {
  const queries = [];
  const conn = {
    async query(sql, params) {
      queries.push({ sql, params });
      if (queries.length === 1) return [{ affectedRows: 1 }];
      return [[{ id: 77, driver_id: 7, status: 'ACCEPTED', accepted_at: ACCEPTED_AT }]];
    },
  };
  const repository = new BookingRepository({});
  const result = await repository.acceptDriverAssignment(conn, 77);

  assert.equal(result.status, 'ACCEPTED');
  assert.match(queries[0].sql, /status = 'ACCEPTED'/);
  assert.match(queries[0].sql, /accepted_at = COALESCE\(accepted_at, CURRENT_TIMESTAMP\)/);
  assert.match(queries[0].sql, /AND status = 'ASSIGNED'/);
  assert.match(queries[1].sql, /FOR UPDATE/);
});

test('route requires authentication and DRIVER role', async () => {
  const unauthorized = await request(app)
    .post(`/api/v1/driver/bookings/${BOOKING_NUMBER}/accept`)
    .send({});
  assert.equal(unauthorized.status, 401);
  assert.equal(unauthorized.body.error_code, ERROR_CODES.UNAUTHORIZED);

  const forbidden = await request(app)
    .post(`/api/v1/driver/bookings/${BOOKING_NUMBER}/accept`)
    .set('Authorization', `Bearer ${sign('CUSTOMER', 55)}`)
    .send({});
  assert.equal(forbidden.status, 403);
  assert.equal(forbidden.body.error_code, ERROR_CODES.FORBIDDEN);
});

test('route preserves 403, 404, and 409 domain error envelopes', async () => {
  const cases = [
    { statusCode: 403, errorCode: ERROR_CODES.DRIVER_INACTIVE },
    { statusCode: 404, errorCode: ERROR_CODES.BOOKING_NOT_FOUND },
    { statusCode: 409, errorCode: ERROR_CODES.BOOKING_NOT_ACCEPTABLE },
  ];

  for (const expected of cases) {
    container.register('driverBookingAcceptanceService', () => ({
      async acceptBooking() {
        throw new AppError('Safe domain error', expected);
      },
    }));
    const response = await request(app)
      .post(`/api/v1/driver/bookings/${BOOKING_NUMBER}/accept`)
      .set('Authorization', `Bearer ${sign()}`)
      .send({});

    assert.equal(response.status, expected.statusCode);
    assert.equal(response.body.success, false);
    assert.equal(response.body.error_code, expected.errorCode);
  }
});

test('route returns standard success envelope', async () => {
  container.register('driverBookingAcceptanceService', () => ({
    async acceptBooking(driverUserId, bookingNumber) {
      assert.equal(driverUserId, 44);
      assert.equal(bookingNumber, BOOKING_NUMBER);
      return {
        bookingNumber,
        bookingStatus: BOOKING_STATUS.DRIVER_ASSIGNED,
        assignmentStatus: 'ACCEPTED',
        acceptedAt: ACCEPTED_AT.toISOString(),
        idempotent: false,
      };
    },
  }));

  const response = await request(app)
    .post(`/api/v1/driver/bookings/${BOOKING_NUMBER}/accept`)
    .set('Authorization', `Bearer ${sign()}`)
    .send({});

  assert.equal(response.status, 200);
  assert.equal(response.body.success, true);
  assert.equal(response.body.message, 'Booking accepted');
  assert.equal(response.body.data.assignmentStatus, 'ACCEPTED');
  assert.equal(response.body.data.bookingStatus, BOOKING_STATUS.DRIVER_ASSIGNED);
});
