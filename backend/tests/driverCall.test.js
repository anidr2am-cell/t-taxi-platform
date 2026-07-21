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
    payment_method: 'PAY_DRIVER',
    commission_amount: 300,
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
    deactivatedAssignments: [],
    deactivatedChatParticipants: [],
    reopened: [],
    notifications: [],
    conflictLookups: [],
    getDetailCalls: [],
  };
  const booking = {
    id: 10,
    booking_number: 'TX202607130001',
    status: BOOKING_STATUS.OPEN,
    vehicle_type_id: 3,
    scheduled_pickup_at: '2026-07-13 10:00:00',
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
    async findOpenDriverCallByBookingId() {
      return overrides.reopenedOpenRow ?? openCallRow();
    },
    async findByBookingNumberForUpdate() {
      return booking;
    },
    async findActiveAssignmentForUpdate() {
      return overrides.activeAssignment ?? null;
    },
    async hasReleasedAssignment() {
      return overrides.hasReleasedAssignment ?? false;
    },
    async insertDriverAssignment(_conn, row) {
      calls.assignments.push(row);
      return 99;
    },
    async updateStatus(_conn, bookingId, status, actorUserId) {
      calls.statusUpdates.push({ bookingId, status, actorUserId });
    },
    async reopenAfterDriverRelease(_conn, bookingId, actorUserId) {
      calls.reopened.push({ bookingId, actorUserId });
      booking.status = BOOKING_STATUS.OPEN;
    },
    async deactivateAssignment(_conn, assignmentId, reason) {
      calls.deactivatedAssignments.push({ assignmentId, reason });
      return overrides.deactivateAssignmentResult ?? true;
    },
    async insertStatusLog(_conn, bookingId, log) {
      calls.statusLogs.push({ bookingId, log });
    },
    async insertActivityLog(_conn, bookingId, activity) {
      calls.activityLogs.push({ bookingId, activity });
    },
    async findActiveDriverBookingByNumberForUpdate() {
      return overrides.detailRow ?? {
        booking_number: booking.booking_number,
        status: BOOKING_STATUS.DRIVER_ASSIGNED,
        assignment_status: 'ASSIGNED',
        scheduled_pickup_at: booking.scheduled_pickup_at,
        pickup_date: '2026-07-13',
        pickup_time: '10:00',
        origin_address: 'BKK Airport',
        destination_address: 'Pattaya Hotel',
        service_type_code: 'AIRPORT_PICKUP',
        service_type_name: 'Airport pickup',
        vehicle_type_code: 'VAN',
        vehicle_type_name: 'Van',
        adults: 2,
        children: 0,
        infants: 0,
        payment_method: 'PAY_DRIVER',
        total_amount: 2500,
        currency: 'THB',
      };
    },
  };
  const driverRepository = {
    async findByUserId() {
      return driver;
    },
    async findByUserIdForUpdate() {
      return driver;
    },
    async hasActiveJob() {
      return overrides.hasActiveJob ?? false;
    },
    async findActiveAssignmentPickupsForConflict() {
      calls.conflictLookups.push({ driverId: driver.id });
      return overrides.conflictRows ?? [];
    },
    async findMatchingVehicle() {
      return overrides.matchingVehicle === false
        ? null
        : { id: 55, vehicle_type_id: 3 };
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
      return overrides.chatRoom === false ? null : { id: 123 };
    },
    async deactivateParticipant(_conn, chatRoomId, participantRole, userId) {
      calls.deactivatedChatParticipants.push({
        chatRoomId,
        participantRole,
        userId,
      });
      return 1;
    },
  };
  const driverJobService = {
    validateBookingNumber(value) {
      return String(value).trim().toUpperCase();
    },
    async getDetail(userId, bookingNumber) {
      calls.getDetailCalls.push({ userId, bookingNumber });
      return {
        bookingNumber: booking.booking_number,
        status: BOOKING_STATUS.DRIVER_ASSIGNED,
        customerPhone: '+66812345678',
      };
    },
    mapDetail(row) {
      return {
        bookingNumber: row.booking_number ?? booking.booking_number,
        status: row.status ?? BOOKING_STATUS.DRIVER_ASSIGNED,
        pickupDate: row.pickup_date ?? '2026-07-13',
        pickupTime: row.pickup_time ?? '10:00',
        customerPhone: '+66812345678',
      };
    },
    paymentSummary(row) {
      const customerPaymentAmount = Number(row.total_amount);
      const companyCommissionAmount =
        row.commission_amount == null ? null : Number(row.commission_amount);
      const safeExpectedIncome =
        Number.isFinite(customerPaymentAmount)
        && Number.isFinite(companyCommissionAmount)
        && customerPaymentAmount >= 0
        && companyCommissionAmount >= 0
        && companyCommissionAmount <= customerPaymentAmount
          ? customerPaymentAmount - companyCommissionAmount
          : null;
      return {
        customerPaymentAmount,
        customerPaymentCurrency: row.currency,
        customerPaymentMethod: row.payment_method,
        companyCommissionAmount,
        companyCommissionCurrency:
          companyCommissionAmount == null ? null : row.currency,
        driverExpectedIncomeAmount: safeExpectedIncome,
        driverExpectedIncomeCurrency: safeExpectedIncome == null ? null : row.currency,
      };
    },
  };
  const commissionSettlementService = {
    async driverHasBlockingSettlement(driverId) {
      if (overrides.blockedDriverIds) {
        return overrides.blockedDriverIds.includes(Number(driverId));
      }
      return overrides.commissionBlocked ?? false;
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
      notificationRepository,
      chatRepository,
      commissionSettlementService,
    ),
  };
}

test('open call list hides customer personal details before assignment', async () => {
  const { service } = createHarness();
  const result = await service.listOpenCalls(42);

  assert.equal(result.items.length, 1);
  assert.equal(result.items[0].bookingNumber, 'TX202607130001');
  assert.equal(result.items[0].amount, 2500);
  assert.equal(result.items[0].customerPaymentAmount, 2500);
  assert.equal(result.items[0].customerPaymentCurrency, 'THB');
  assert.equal(result.items[0].customerPaymentMethod, 'PAY_DRIVER');
  assert.equal(result.items[0].companyCommissionAmount, 300);
  assert.equal(result.items[0].companyCommissionCurrency, 'THB');
  assert.equal(result.items[0].driverExpectedIncomeAmount, 2200);
  assert.equal(result.items[0].driverExpectedIncomeCurrency, 'THB');
  assert.equal(result.items[0].luggage.golfBags, 1);
  assert.equal(Object.hasOwn(result.items[0], 'customerPhone'), false);
  assert.equal(Object.hasOwn(result.items[0], 'customerEmail'), false);
  assert.equal(Object.hasOwn(result.items[0], 'specialInstructions'), false);
});

test('open call list keeps unsafe expected income nullable', async () => {
  const { service } = createHarness({
    openRows: [openCallRow({ total_amount: 1300, commission_amount: 1500 })],
  });
  const result = await service.listOpenCalls(42);

  assert.equal(result.items[0].customerPaymentAmount, 1300);
  assert.equal(result.items[0].companyCommissionAmount, 1500);
  assert.equal(result.items[0].driverExpectedIncomeAmount, null);
  assert.equal(result.items[0].driverExpectedIncomeCurrency, null);
});

test('open call list hides calls when settlement confirmation is required', async () => {
  const { service } = createHarness({ commissionBlocked: true });

  const result = await service.listOpenCalls(42);

  assert.deepEqual(result, {
    items: [],
    blockedReason: 'UNPAID_SETTLEMENT',
    message: 'ยังไม่สามารถรับงานใหม่ได้ กรุณาชำระค่าคอมมิชชั่นและรอการตรวจสอบจากแอดมิน',
  });
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
  assert.equal(result.bookingNumber, 'TX202607130001');
  assert.equal(result.booking.bookingNumber, 'TX202607130001');
  setRealtimeIo(null);
});

test('claimOpenCall allows pickup times exactly 3 hours apart', async () => {
  const { service, conn, calls } = createHarness({
    conflictRows: [{
      id: 5,
      booking_number: 'TX202607120001',
      scheduled_pickup_at: '2026-07-13 13:00:00',
    }],
    booking: { scheduled_pickup_at: '2026-07-13 10:00:00' },
  });

  const result = await service.claimOpenCall(42, 'TX202607130001');

  assert.equal(result.status, BOOKING_STATUS.DRIVER_ASSIGNED);
  assert.equal(conn.committed, true);
  assert.equal(calls.conflictLookups.length, 1);
});

test('claimOpenCall rejects pickup conflict even when hasActiveJob is false', async () => {
  const { service, calls } = createHarness({
    hasActiveJob: false,
    conflictRows: [{
      id: 5,
      booking_number: 'TX202607120001',
      scheduled_pickup_at: '2026-07-13 11:00:00',
    }],
    booking: { scheduled_pickup_at: '2026-07-13 10:00:00' },
  });

  await assert.rejects(
    () => service.claimOpenCall(42, 'TX202607130001'),
    (err) => err.statusCode === 409 && err.errorCode === ERROR_CODES.DRIVER_BOOKING_TIME_CONFLICT,
  );
  assert.equal(calls.conflictLookups.length, 1);
});

test('claimOpenCall returns booking detail mapped inside transaction', async () => {
  const { service, calls } = createHarness({
    detailRow: {
      booking_number: 'TX202607130001',
      status: BOOKING_STATUS.DRIVER_ASSIGNED,
      assignment_status: 'ASSIGNED',
      pickup_date: '2026-07-13',
      pickup_time: '10:30',
    },
  });

  const result = await service.claimOpenCall(42, 'TX202607130001');

  assert.equal(result.booking.pickupTime, '10:30');
  assert.equal(result.booking.bookingNumber, 'TX202607130001');
  assert.deepEqual(calls.getDetailCalls, []);
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

  const busy = createHarness({
    conflictRows: [{
      id: 5,
      booking_number: 'TX202607120001',
      scheduled_pickup_at: '2026-07-13 11:00:00',
    }],
  });
  await assert.rejects(
    () => busy.service.claimOpenCall(42, 'TX202607130001'),
    (err) => err.statusCode === 409 && err.errorCode === ERROR_CODES.DRIVER_BOOKING_TIME_CONFLICT,
  );
});

test('claimOpenCall rejects settlement-blocked drivers', async () => {
  const { service, conn } = createHarness({ commissionBlocked: true });

  await assert.rejects(
    () => service.claimOpenCall(42, 'TX202607130001'),
    (err) => err.statusCode === 409 && err.errorCode === ERROR_CODES.DRIVER_NOT_ELIGIBLE,
  );
  assert.equal(conn.rolledBack, true);
});

test('claimOpenCall rejects vehicle type mismatch', async () => {
  const { service } = createHarness({ matchingVehicle: false });

  await assert.rejects(
    () => service.claimOpenCall(42, 'TX202607130001'),
    (err) => err.statusCode === 409 && err.errorCode === ERROR_CODES.DRIVER_NOT_ELIGIBLE,
  );
});

test('releaseAssignment reopens booking, clears active assignment, and notifies other drivers', async () => {
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
  const { service, conn, calls } = createHarness({
    booking: { status: BOOKING_STATUS.DRIVER_ASSIGNED },
    activeAssignment: { id: 77, driver_id: 7, status: 'ASSIGNED', is_active: 1 },
  });

  const result = await service.releaseAssignment(42, 'TX202607130001');

  assert.equal(result.status, BOOKING_STATUS.OPEN);
  assert.equal(result.released, true);
  assert.equal(conn.committed, true);
  assert.equal(conn.rolledBack, false);
  assert.deepEqual(calls.deactivatedAssignments[0], {
    assignmentId: 77,
    reason: 'DRIVER_RELEASED_ASSIGNMENT',
  });
  assert.deepEqual(calls.reopened[0], { bookingId: 10, actorUserId: 42 });
  assert.deepEqual(calls.deactivatedChatParticipants[0], {
    chatRoomId: 123,
    participantRole: 'DRIVER',
    userId: 42,
  });
  assert.equal(calls.statusLogs[0].log.fromStatus, BOOKING_STATUS.DRIVER_ASSIGNED);
  assert.equal(calls.statusLogs[0].log.toStatus, BOOKING_STATUS.OPEN);
  assert.equal(calls.statusLogs[0].log.reason, 'DRIVER_RELEASED_ASSIGNMENT');
  assert.equal(calls.notifications.length, 2);
  assert.equal(calls.notifications[0].notificationType, NOTIFICATION_TYPES.DRIVER_CALL_AVAILABLE);
  assert.equal(Object.hasOwn(calls.notifications[0].payload, 'customerPhone'), false);
  assert.equal(
    emitted.some((row) => row.room === driverUserRoom(42) && row.event === 'driver:assignment:released'),
    true,
  );
  assert.equal(
    emitted.filter((row) => row.event === 'driver:call:new').length,
    2,
  );
  setRealtimeIo(null);
});

test('releaseAssignment excludes settlement-blocked drivers from reopened call notifications', async () => {
  const { service, calls } = createHarness({
    booking: { status: BOOKING_STATUS.DRIVER_ASSIGNED },
    activeAssignment: { id: 77, driver_id: 7, status: 'ASSIGNED', is_active: 1 },
    eligibleDrivers: [
      { id: 8, user_id: 43 },
      { id: 9, user_id: 44 },
    ],
    blockedDriverIds: [9],
  });

  const result = await service.releaseAssignment(42, 'TX202607130001');

  assert.equal(result.released, true);
  assert.equal(calls.notifications.length, 1);
  assert.equal(calls.notifications[0].recipientDriverId, 8);
});

test('releaseAssignment rejects wrong driver and started trip', async () => {
  const wrongDriver = createHarness({
    booking: { status: BOOKING_STATUS.DRIVER_ASSIGNED },
    activeAssignment: { id: 77, driver_id: 99, status: 'ASSIGNED', is_active: 1 },
  });
  await assert.rejects(
    () => wrongDriver.service.releaseAssignment(42, 'TX202607130001'),
    (err) => err.statusCode === 409 && err.errorCode === ERROR_CODES.BOOKING_NOT_ASSIGNED_TO_DRIVER,
  );
  assert.equal(wrongDriver.conn.rolledBack, true);

  const started = createHarness({
    booking: { status: BOOKING_STATUS.DRIVER_ARRIVED },
    activeAssignment: { id: 77, driver_id: 7, status: 'ASSIGNED', is_active: 1 },
  });
  await assert.rejects(
    () => started.service.releaseAssignment(42, 'TX202607130001'),
    (err) => err.statusCode === 409 && err.errorCode === ERROR_CODES.BOOKING_RELEASE_NOT_ALLOWED,
  );
});

test('releaseAssignment keeps existing compatibility for ACCEPTED assignment', async () => {
  const { service, conn, calls } = createHarness({
    booking: { status: BOOKING_STATUS.DRIVER_ASSIGNED },
    activeAssignment: { id: 77, driver_id: 7, status: 'ACCEPTED', is_active: 1 },
  });

  const result = await service.releaseAssignment(42, 'TX202607130001');

  assert.equal(result.released, true);
  assert.equal(conn.committed, true);
  assert.equal(calls.deactivatedAssignments.length, 1);
});

test('releaseAssignment duplicate request returns conflict without reopening again', async () => {
  const { service, conn, calls } = createHarness({
    booking: { status: BOOKING_STATUS.OPEN },
    activeAssignment: null,
    hasReleasedAssignment: true,
  });

  await assert.rejects(
    () => service.releaseAssignment(42, 'TX202607130001'),
    (err) => err.statusCode === 409 && err.errorCode === ERROR_CODES.ASSIGNMENT_ALREADY_RELEASED,
  );
  assert.equal(conn.rolledBack, true);
  assert.equal(calls.reopened.length, 0);
  assert.equal(calls.notifications.length, 0);
});

test('releaseAssignment rolls back and emits no events when reopening fails', async () => {
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
  const { service, conn } = createHarness({
    booking: { status: BOOKING_STATUS.DRIVER_ASSIGNED },
    activeAssignment: { id: 77, driver_id: 7, status: 'ASSIGNED', is_active: 1 },
  });
  service.bookingRepository.reopenAfterDriverRelease = async () => {
    throw new Error('update failed');
  };

  await assert.rejects(
    () => service.releaseAssignment(42, 'TX202607130001'),
    /update failed/,
  );
  assert.equal(conn.rolledBack, true);
  assert.equal(conn.committed, false);
  assert.equal(emitted.length, 0);
  setRealtimeIo(null);
});

test('claimOpenCall rejects a booking previously released by the same driver', async () => {
  const { service } = createHarness({ hasReleasedAssignment: true });

  await assert.rejects(
    () => service.claimOpenCall(42, 'TX202607130001'),
    (err) => err.statusCode === 409 && err.errorCode === ERROR_CODES.ASSIGNMENT_ALREADY_RELEASED,
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

test('booking creation helper excludes settlement-blocked drivers from open call notifications', async () => {
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
    {
      async driverHasBlockingSettlement(driverId) {
        return Number(driverId) === 8;
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

  assert.deepEqual(targets, [{ driverId: 7, userId: 42 }]);
  assert.equal(inserted.length, 1);
  assert.equal(inserted[0].recipientDriverId, 7);
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
