const test = require('node:test');
const assert = require('node:assert/strict');

process.env.NODE_ENV = process.env.NODE_ENV || 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'tride_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret';

const DriverCallService = require('../src/services/driverCall.service');
const BookingService = require('../src/services/booking.service');
const BOOKING_STATUS = require('../src/constants/reservationStatus');
const ERROR_CODES = require('../src/constants/errorCodes');
const NOTIFICATION_TYPES = require('../src/constants/notificationTypes');
const { registerDriverCallHandlers } = require('../src/socket/handlers/driverCalls.handler');
const { DRIVER_ALL_ROOM, driverUserRoom, setRealtimeIo } = require('../src/socket/realtime');

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

function createPool(conn = createConn()) {
  return {
    conn,
    async getConnection() { return conn; },
  };
}

function openCallRow(overrides = {}) {
  return {
    booking_number: 'TX202607130001',
    status: BOOKING_STATUS.OPEN,
    pickup_date: '2026-07-13',
    pickup_time: '10:30',
    origin_address: 'BKK Airport',
    destination_address: 'Pattaya Hotel',
    total_amount: 2500,
    currency: 'THB',
    service_type_code: 'AIRPORT_PICKUP',
    service_type_name: 'Airport pickup',
    vehicle_type_code: 'VAN',
    vehicle_type_name: 'Van',
    adults: 2,
    children: 1,
    infants: 0,
    carriers_20_inch: 1,
    carriers_24_inch_plus: 2,
    golf_bags: 1,
    special_items: 'folding stroller',
    ...overrides,
  };
}

function createHarness(overrides = {}) {
  const conn = createConn();
  const pool = createPool(conn);
  const calls = {
    assignments: [],
    statusUpdates: [],
    statusLogs: [],
    activityLogs: [],
  };
  const booking = {
    id: 10,
    booking_number: 'TX202607130001',
    status: BOOKING_STATUS.OPEN,
    vehicle_type_id: 3,
    ...overrides.booking,
  };
  const driver = {
    id: 7,
    user_id: 42,
    name: 'Somchai',
    is_active: 1,
    user_is_active: 1,
    is_online: 1,
    status: 'AVAILABLE',
    ...overrides.driver,
  };
  const bookingRepository = {
    async findOpenDriverCallsForDriver() {
      return overrides.openRows ?? [openCallRow()];
    },
    async findByBookingNumberForUpdate() {
      return booking;
    },
    async findActiveAssignmentForUpdate() {
      return overrides.activeAssignment ?? null;
    },
    async insertDriverAssignment(_conn, row) {
      calls.assignments.push(row);
      return 99;
    },
    async updateStatus(_conn, bookingId, status, actorUserId) {
      calls.statusUpdates.push({ bookingId, status, actorUserId });
    },
    async insertStatusLog(_conn, bookingId, log) {
      calls.statusLogs.push({ bookingId, log });
    },
    async insertActivityLog(_conn, bookingId, activity) {
      calls.activityLogs.push({ bookingId, activity });
    },
  };
  const driverRepository = {
    async findByUserIdForUpdate() {
      return driver;
    },
    async hasActiveJob() {
      return overrides.hasActiveJob ?? false;
    },
    async findMatchingVehicle() {
      return overrides.matchingVehicle === false
        ? null
        : { id: 55, vehicle_type_id: 3 };
    },
  };
  const driverJobService = {
    validateBookingNumber(value) {
      return String(value).trim().toUpperCase();
    },
    async getDetail() {
      return {
        bookingNumber: booking.booking_number,
        status: BOOKING_STATUS.DRIVER_ASSIGNED,
        customerPhone: '+66812345678',
      };
    },
  };
  return {
    conn,
    calls,
    service: new DriverCallService(
      pool,
      bookingRepository,
      driverRepository,
      driverJobService,
    ),
  };
}

test('open call list hides customer personal details before assignment', async () => {
  const { service } = createHarness();
  const result = await service.listOpenCalls(42);

  assert.equal(result.items.length, 1);
  assert.equal(result.items[0].bookingNumber, 'TX202607130001');
  assert.equal(result.items[0].amount, 2500);
  assert.equal(result.items[0].luggage.golfBags, 1);
  assert.equal(Object.hasOwn(result.items[0], 'customerPhone'), false);
  assert.equal(Object.hasOwn(result.items[0], 'customerEmail'), false);
  assert.equal(Object.hasOwn(result.items[0], 'specialInstructions'), false);
});

test('claimOpenCall atomically creates assignment and moves booking to DRIVER_ASSIGNED', async () => {
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
  const { service, conn, calls } = createHarness();

  const result = await service.claimOpenCall(42, 'TX202607130001');

  assert.equal(result.status, BOOKING_STATUS.DRIVER_ASSIGNED);
  assert.equal(conn.committed, true);
  assert.equal(conn.rolledBack, false);
  assert.equal(calls.assignments.length, 1);
  assert.deepEqual(calls.statusUpdates[0], {
    bookingId: 10,
    status: BOOKING_STATUS.DRIVER_ASSIGNED,
    actorUserId: 42,
  });
  assert.equal(calls.statusLogs[0].log.fromStatus, BOOKING_STATUS.OPEN);
  assert.equal(calls.statusLogs[0].log.toStatus, BOOKING_STATUS.DRIVER_ASSIGNED);
  assert.equal(emitted.some((row) => row.event === 'driver:call:claimed'), true);
  assert.equal(
    emitted.some((row) => row.room === driverUserRoom(42) && row.event === 'driver:call:confirmed'),
    true,
  );
  setRealtimeIo(null);
});

test('claimOpenCall returns 409 when another driver already claimed booking', async () => {
  const { service, conn } = createHarness({
    booking: { status: BOOKING_STATUS.DRIVER_ASSIGNED },
  });

  await assert.rejects(
    () => service.claimOpenCall(42, 'TX202607130001'),
    (err) => err.statusCode === 409 && err.errorCode === ERROR_CODES.ALREADY_ASSIGNED,
  );
  assert.equal(conn.rolledBack, true);
});

test('claimOpenCall rejects offline or busy drivers', async () => {
  const offline = createHarness({ driver: { is_online: 0, status: 'OFFLINE' } });
  await assert.rejects(
    () => offline.service.claimOpenCall(42, 'TX202607130001'),
    (err) => err.statusCode === 409 && err.errorCode === ERROR_CODES.DRIVER_NOT_AVAILABLE,
  );

  const busy = createHarness({ hasActiveJob: true });
  await assert.rejects(
    () => busy.service.claimOpenCall(42, 'TX202607130001'),
    (err) => err.statusCode === 409 && err.errorCode === ERROR_CODES.DRIVER_NOT_AVAILABLE,
  );
});

test('claimOpenCall rejects vehicle type mismatch', async () => {
  const { service } = createHarness({ matchingVehicle: false });

  await assert.rejects(
    () => service.claimOpenCall(42, 'TX202607130001'),
    (err) => err.statusCode === 409 && err.errorCode === ERROR_CODES.DRIVER_NOT_ELIGIBLE,
  );
});

test('booking creation helper stores notifications for eligible online drivers', async () => {
  const inserted = [];
  const service = new BookingService(
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    {
      async listEligibleForOpenBooking() {
        return [
          { id: 7, user_id: 42 },
          { id: 8, user_id: 43 },
        ];
      },
    },
    {
      async insert(_conn, row) {
        inserted.push(row);
      },
    },
  );

  const targets = await service.notifyEligibleDriversForOpenBooking({}, {
    bookingId: 10,
    bookingNumber: 'TX202607130001',
    vehicleTypeId: 3,
    openCallPayload: {
      bookingNumber: 'TX202607130001',
      origin: 'BKK',
      destination: 'Pattaya',
    },
  });

  assert.deepEqual(targets, [
    { driverId: 7, userId: 42 },
    { driverId: 8, userId: 43 },
  ]);
  assert.equal(inserted.length, 2);
  assert.equal(inserted[0].notificationType, NOTIFICATION_TYPES.DRIVER_CALL_AVAILABLE);
  assert.equal(inserted[0].recipientDriverId, 7);
  assert.equal(inserted[0].userId, 42);
});

test('driver call socket handler joins driver rooms and rejects non-drivers', async () => {
  const handlers = {};
  const joinedRooms = new Set();
  const emitted = [];
  const socket = {
    data: { authUser: { id: 42, role: 'DRIVER' } },
    on(event, handler) { handlers[event] = handler; },
    async join(room) { joinedRooms.add(room); },
    emit(event, payload) { emitted.push({ event, payload }); },
  };
  registerDriverCallHandlers({}, socket);
  await handlers['driver:calls:subscribe']({}, () => {});
  assert.equal(joinedRooms.has(DRIVER_ALL_ROOM), true);
  assert.equal(joinedRooms.has(driverUserRoom(42)), true);

  const customerHandlers = {};
  const customerSocket = {
    data: { authUser: { id: 9, role: 'CUSTOMER' } },
    on(event, handler) { customerHandlers[event] = handler; },
    async join() {},
    emit(event, payload) { emitted.push({ event, payload }); },
  };
  registerDriverCallHandlers({}, customerSocket);
  let ack;
  await customerHandlers['driver:calls:subscribe']({}, (value) => { ack = value; });
  assert.equal(ack.ok, false);
  assert.equal(ack.error.code, ERROR_CODES.FORBIDDEN);
});
