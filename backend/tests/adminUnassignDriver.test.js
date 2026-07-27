process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const jwt = require('jsonwebtoken');
const request = require('supertest');

const app = require('../src/app');
const container = require('../src/helpers/container');
const AdminDispatchService = require('../src/services/adminDispatch.service');
const BookingAssignmentReopenService = require('../src/services/bookingAssignmentReopen.service');
const DriverCallService = require('../src/services/driverCall.service');
const DriverJobService = require('../src/services/driverJob.service');
const BOOKING_STATUS = require('../src/constants/reservationStatus');
const ERROR_CODES = require('../src/constants/errorCodes');
const ROLES = require('../src/constants/roles');
const {
  ADMIN_ASSIGNMENT_RELEASE_MARKER,
  ADMIN_UNASSIGN_ACTIVITY_TYPE,
  ADMIN_RELEASED_REASON_CODE,
} = require('../src/constants/bookingAssignmentRelease.constants');
const { driverUserRoom, setRealtimeIo } = require('../src/socket/realtime');

function sign(role = 'ADMIN', id = 1) {
  return jwt.sign(
    { sub: id, email: `${role.toLowerCase()}@example.com`, role, type: 'access' },
    process.env.JWT_ACCESS_SECRET,
    { expiresIn: '1h' },
  );
}

function createConn() {
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

function openCallRow() {
  return {
    booking_number: 'TX202607010001',
    status: BOOKING_STATUS.OPEN,
    pickup_date: '2026-07-01',
    pickup_time: '09:30',
    origin_address: 'BKK Airport',
    destination_address: 'Pattaya Hotel',
    total_amount: 2500,
    currency: 'THB',
    payment_method: 'PAY_DRIVER',
    commission_amount: 300,
    service_type_code: 'AIRPORT_PICKUP',
    service_type_name: 'Airport pickup',
    vehicle_type_code: 'SUV',
    vehicle_type_name: 'SUV',
    adults: 2,
    children: 0,
    infants: 0,
    carriers_20_inch: 0,
    carriers_24_inch_plus: 0,
    golf_bags: 0,
    special_items: null,
    name_sign_requested: 0,
    name_sign_text: null,
    is_exact_vehicle_match: 1,
  };
}

function createServiceHarness(overrides = {}) {
  const conn = createConn();
  const pool = { async getConnection() { return conn; } };
  const calls = {
    deactivatedAssignments: [],
    reopened: [],
    statusLogs: [],
    activityLogs: [],
    notifications: [],
    deactivatedChatParticipants: [],
  };
  const booking = {
    id: 10,
    booking_number: 'TX202607010001',
    status: BOOKING_STATUS.DRIVER_ASSIGNED,
    vehicle_type_id: 2,
    driver_user_id: 99,
    scheduled_pickup_at: '2026-07-01 09:30:00',
    is_urgent_request: 0,
    ...overrides.booking,
  };
  const activeAssignment = overrides.activeAssignment === null
    ? null
    : {
      id: 77,
      driver_id: 7,
      status: 'ASSIGNED',
      is_active: 1,
      ...overrides.activeAssignment,
    };
  const bookingRepository = {
    async findByBookingNumberForUpdate() {
      return overrides.booking === false ? null : booking;
    },
    async findActiveAssignmentForUpdate() {
      return activeAssignment;
    },
    async deactivateAssignment(_conn, assignmentId, reason) {
      calls.deactivatedAssignments.push({ assignmentId, reason });
      return overrides.deactivateAssignmentResult ?? true;
    },
    async reopenAfterDriverRelease(_conn, bookingId, actorUserId) {
      calls.reopened.push({ bookingId, actorUserId });
      booking.status = BOOKING_STATUS.OPEN;
    },
    async insertStatusLog(_conn, bookingId, log) {
      calls.statusLogs.push({ bookingId, log });
    },
    async insertActivityLog(_conn, bookingId, activity) {
      calls.activityLogs.push({ bookingId, activity });
    },
    async findOpenDriverCallByBookingId() {
      return openCallRow();
    },
  };
  const driverRepository = {
    async findById(driverId) {
      return overrides.driver ?? { id: driverId, user_id: 99, name: 'Somchai' };
    },
    async listEligibleForOpenBooking() {
      return overrides.eligibleDrivers ?? [
        { id: 8, user_id: 43 },
        { id: 9, user_id: 44 },
      ];
    },
  };
  const notificationRepository = {
    async insert(_conn, row) {
      calls.notifications.push(row);
    },
  };
  const chatRepository = {
    async findRoomByBookingIdForUpdate() {
      return { id: 123 };
    },
    async deactivateParticipant(_conn, chatRoomId, participantRole, userId) {
      calls.deactivatedChatParticipants.push({ chatRoomId, participantRole, userId });
    },
  };
  const driverJobService = new DriverJobService(null);
  const driverCallService = new DriverCallService(
    pool,
    bookingRepository,
    driverRepository,
    driverJobService,
    notificationRepository,
    chatRepository,
    null,
    null,
    new BookingAssignmentReopenService(
      bookingRepository,
      driverRepository,
      notificationRepository,
      chatRepository,
    ),
  );
  const bookingAssignmentReopenService = new BookingAssignmentReopenService(
    bookingRepository,
    driverRepository,
    notificationRepository,
    chatRepository,
  );
  const service = new AdminDispatchService(
    pool,
    bookingRepository,
    driverRepository,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    bookingAssignmentReopenService,
    driverCallService,
  );

  return {
    conn,
    calls,
    booking,
    service,
  };
}

test('unassignDriver reopens booking, deactivates assignment, and notifies drivers', async () => {
  const emitted = [];
  setRealtimeIo({
    to(room) {
      return {
        emit(event, payload) {
          emitted.push({ room, event, payload });
        },
      };
    },
  });

  const { service, conn, calls } = createServiceHarness();
  const result = await service.unassignDriver(
    'TX202607010001',
    { reason: 'Driver unavailable' },
    { id: 1, role: ROLES.ADMIN },
  );

  assert.equal(result.status, BOOKING_STATUS.OPEN);
  assert.equal(result.unassigned, true);
  assert.equal(result.previousDriverId, 7);
  assert.equal(conn.committed, true);
  assert.deepEqual(calls.deactivatedAssignments[0], {
    assignmentId: 77,
    reason: ADMIN_ASSIGNMENT_RELEASE_MARKER,
  });
  assert.equal(calls.statusLogs[0].log.fromStatus, BOOKING_STATUS.DRIVER_ASSIGNED);
  assert.equal(calls.statusLogs[0].log.toStatus, BOOKING_STATUS.OPEN);
  assert.equal(calls.statusLogs[0].log.reason, ADMIN_ASSIGNMENT_RELEASE_MARKER);
  assert.equal(calls.activityLogs[0].activity.activityType, ADMIN_UNASSIGN_ACTIVITY_TYPE);
  assert.equal(calls.activityLogs[0].activity.actorRole, ROLES.ADMIN);
  assert.equal(calls.notifications.length, 2);

  const releaseEvent = emitted.find(
    (row) => row.room === driverUserRoom(99) && row.event === 'driver:assignment:released',
  );
  assert.ok(releaseEvent);
  assert.equal(releaseEvent.payload.reasonCode, ADMIN_RELEASED_REASON_CODE);
  assert.equal(
    emitted.filter((row) => row.event === 'driver:call:new').length,
    2,
  );
  setRealtimeIo(null);
});

test('unassignDriver rejects non DRIVER_ASSIGNED status', async () => {
  const { service, conn } = createServiceHarness({
    booking: { status: BOOKING_STATUS.ON_ROUTE },
  });

  await assert.rejects(
    () => service.unassignDriver(
      'TX202607010001',
      { reason: 'Too late' },
      { id: 1, role: ROLES.ADMIN },
    ),
    (err) => err.statusCode === 409
      && err.errorCode === ERROR_CODES.INVALID_STATUS_FOR_UNASSIGN,
  );
  assert.equal(conn.rolledBack, true);
});

test('unassignDriver rejects when no active assignment', async () => {
  const { service, conn } = createServiceHarness({ activeAssignment: null });

  await assert.rejects(
    () => service.unassignDriver(
      'TX202607010001',
      { reason: 'No driver' },
      { id: 1, role: ROLES.ADMIN },
    ),
    (err) => err.statusCode === 409
      && err.errorCode === ERROR_CODES.NO_ACTIVE_ASSIGNMENT,
  );
  assert.equal(conn.rolledBack, true);
});

test('ADMIN can call unassign-driver route', async () => {
  container.register('adminDispatchService', () => ({
    async unassignDriver(_bookingNumber, input) {
      return {
        bookingNumber: 'TX202607010001',
        status: BOOKING_STATUS.OPEN,
        unassigned: true,
        previousDriverId: 7,
        reason: input.reason,
      };
    },
  }));

  const res = await request(app)
    .post('/api/v1/admin/bookings/TX202607010001/unassign-driver')
    .set('Authorization', `Bearer ${sign('ADMIN')}`)
    .send({ reason: 'Schedule conflict' });

  assert.equal(res.status, 200);
  assert.equal(res.body.data.status, BOOKING_STATUS.OPEN);
  assert.equal(res.body.data.unassigned, true);
});

test('unassign-driver rejects missing reason', async () => {
  const res = await request(app)
    .post('/api/v1/admin/bookings/TX202607010001/unassign-driver')
    .set('Authorization', `Bearer ${sign('ADMIN')}`)
    .send({});

  assert.equal(res.status, 400);
  assert.equal(res.body.error_code, ERROR_CODES.VALIDATION_ERROR);
});

test('DRIVER cannot call unassign-driver route', async () => {
  container.register('adminDispatchService', () => ({
    async unassignDriver() {
      return { status: BOOKING_STATUS.OPEN };
    },
  }));

  const res = await request(app)
    .post('/api/v1/admin/bookings/TX202607010001/unassign-driver')
    .set('Authorization', `Bearer ${sign('DRIVER', 9)}`)
    .send({ reason: 'Should fail' });

  assert.equal(res.status, 403);
});
