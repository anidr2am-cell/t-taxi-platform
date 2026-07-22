const { afterEach, test } = require('node:test');
const assert = require('node:assert/strict');

process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const BookingStatusService = require('../src/services/bookingStatus.service');
const AppError = require('../src/utils/AppError');
const ERROR_CODES = require('../src/constants/errorCodes');
const ROLES = require('../src/constants/roles');
const BOOKING_STATUS = require('../src/constants/reservationStatus');
const { appEvents, EVENTS } = require('../src/events');

const actor = { id: 7, role: ROLES.ADMIN };

function createBooking(overrides = {}) {
  return {
    id: 10,
    booking_number: 'TX202607010001',
    status: 'PENDING',
    total_amount: '1600.00',
    currency: 'THB',
    payment_status: 'UNPAID',
    payment_method: 'PAY_DRIVER',
    customer_user_id: 55,
    driver_id: 9,
    driver_user_id: 99,
    scheduled_pickup_at: '2026-07-25 15:00:00',
    ...overrides,
  };
}

function createHarness({ booking = createBooking(), commitError = null } = {}) {
  const calls = {
    beginTransaction: 0,
    commit: 0,
    rollback: 0,
    release: 0,
    updateStatus: 0,
    insertStatusLog: 0,
    insertActivityLog: 0,
    outboxInsert: 0,
    outboxDispatch: 0,
  };
  const records = {};
  const conn = {
    async beginTransaction() {
      calls.beginTransaction += 1;
    },
    async commit() {
      calls.commit += 1;
      if (commitError) throw commitError;
    },
    async rollback() {
      calls.rollback += 1;
    },
    release() {
      calls.release += 1;
    },
  };
  const pool = {
    async getConnection() {
      return conn;
    },
  };
  const repository = {
    async findByBookingNumberForUpdate() {
      return booking;
    },
    async updateStatus(_conn, bookingId, status, actorUserId, statusFields) {
      calls.updateStatus += 1;
      records.updateStatus = { bookingId, status, actorUserId, statusFields };
    },
    async insertStatusLog(_conn, bookingId, log) {
      calls.insertStatusLog += 1;
      records.statusLog = { bookingId, log };
    },
    async insertActivityLog(_conn, bookingId, activity) {
      calls.insertActivityLog += 1;
      records.activityLog = { bookingId, activity };
    },
    async updateCommissionFields() {},
    async completeActiveAssignment(_conn, bookingId) {
      calls.completeActiveAssignment = (calls.completeActiveAssignment ?? 0) + 1;
      records.completeActiveAssignment = { bookingId };
    },
    async clearAssignmentOnCancel(_conn, bookingId, actorUserId, reason) {
      calls.clearAssignmentOnCancel = (calls.clearAssignmentOnCancel ?? 0) + 1;
      records.clearAssignmentOnCancel = { bookingId, actorUserId, reason };
      return { id: 1, driver_id: booking.driver_id };
    },
    async findActiveGuestTokenForBooking() {
      return { id: 1 };
    },
  };
  const outboxRepository = {
    async insertNotificationEvent(_conn, data) {
      calls.outboxInsert += 1;
      records.outbox = data;
      return 42;
    },
  };
  const outboxProcessor = {
    async dispatchOutboxIds(ids) {
      calls.outboxDispatch += 1;
      records.dispatchedIds = ids;
    },
  };

  return {
    calls,
    records,
    service: new BookingStatusService(pool, repository, outboxRepository, outboxProcessor),
  };
}

function collectEvents(eventName) {
  const events = [];
  const listener = (payload) => events.push(payload);
  appEvents.on(eventName, listener);
  return {
    events,
    stop() {
      appEvents.off(eventName, listener);
    },
  };
}

afterEach(() => {
  appEvents.removeAllListeners(EVENTS.BOOKING_CONFIRMED);
});

test('valid transition writes logs and outbox event after commit', async () => {
  const harness = createHarness();

  const result = await harness.service.transition(
    'TX202607010001',
    { status: 'CONFIRMED', reason: 'PAYMENT_CONFIRMED', memo: 'manual confirm' },
    actor,
  );

  assert.equal(result.status, 'CONFIRMED');
  assert.equal(result.idempotent, false);
  assert.equal(harness.calls.updateStatus, 1);
  assert.equal(harness.calls.insertStatusLog, 1);
  assert.equal(harness.calls.insertActivityLog, 1);
  assert.equal(harness.calls.commit, 1);
  assert.equal(harness.calls.rollback, 0);
  assert.equal(harness.calls.outboxInsert, 1);
  assert.equal(harness.calls.outboxDispatch, 1);
  assert.deepEqual(harness.records.dispatchedIds, [42]);

  assert.deepEqual(harness.records.activityLog.activity.payload, {
    bookingNumber: 'TX202607010001',
    previousStatus: 'PENDING',
    newStatus: 'CONFIRMED',
    changedByUserId: 7,
    changedByRole: 'ADMIN',
    occurredAt: harness.records.activityLog.activity.payload.occurredAt,
    driverId: 9,
    reason: 'PAYMENT_CONFIRMED',
    memo: 'manual confirm',
  });
  assert.match(harness.records.activityLog.activity.payload.occurredAt, /^\d{4}-\d{2}-\d{2}T/);

  assert.equal(harness.records.outbox.eventType, EVENTS.BOOKING_CONFIRMED);
  assert.equal(harness.records.outbox.aggregateId, 10);
  const event = harness.records.outbox.payload;
  assert.equal(event.eventName, EVENTS.BOOKING_CONFIRMED);
  assert.match(event.eventId, /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i);
  assert.equal(event.bookingId, 10);
  assert.equal(event.bookingNumber, 'TX202607010001');
  assert.equal(event.previousStatus, 'PENDING');
  assert.equal(event.newStatus, 'CONFIRMED');
  assert.equal(event.actorUserId, 7);
  assert.equal(event.actorRole, 'ADMIN');
  assert.equal(event.driverId, 9);
  assert.equal(event.occurredAt, harness.records.activityLog.activity.payload.occurredAt);
});

test('invalid transition returns INVALID_STATUS_TRANSITION', async () => {
  const harness = createHarness();

  await assert.rejects(
    () => harness.service.transition('TX202607010001', { status: 'COMPLETED' }, actor),
    (err) => err instanceof AppError
      && err.errorCode === ERROR_CODES.INVALID_STATUS_TRANSITION,
  );

  assert.equal(harness.calls.updateStatus, 0);
  assert.equal(harness.calls.insertStatusLog, 0);
  assert.equal(harness.calls.insertActivityLog, 0);
  assert.equal(harness.calls.rollback, 1);
});

test('same-status request is idempotent and creates no duplicate side effects', async () => {
  const harness = createHarness({ booking: createBooking({ status: 'PICKED_UP' }) });
  const collector = collectEvents(EVENTS.TRIP_PICKED_UP);

  const result = await harness.service.transition(
    'TX202607010001',
    { status: 'PICKED_UP' },
    actor,
  );

  collector.stop();

  assert.equal(result.status, 'PICKED_UP');
  assert.equal(result.idempotent, true);
  assert.equal(harness.calls.updateStatus, 0);
  assert.equal(harness.calls.insertStatusLog, 0);
  assert.equal(harness.calls.insertActivityLog, 0);
  assert.equal(harness.calls.commit, 1);
  assert.equal(harness.calls.rollback, 0);
  assert.equal(collector.events.length, 0);
});

test('repeated same-status request does not duplicate logs', async () => {
  const harness = createHarness({ booking: createBooking({ status: 'CONFIRMED' }) });

  await harness.service.transition('TX202607010001', { status: 'CONFIRMED' }, actor);
  await harness.service.transition('TX202607010001', { status: 'CONFIRMED' }, actor);

  assert.equal(harness.calls.updateStatus, 0);
  assert.equal(harness.calls.insertStatusLog, 0);
  assert.equal(harness.calls.insertActivityLog, 0);
  assert.equal(harness.calls.commit, 2);
});

test('transaction failure prevents outbox dispatch', async () => {
  const harness = createHarness({ commitError: new Error('commit failed') });

  await assert.rejects(
    () => harness.service.transition('TX202607010001', { status: 'CONFIRMED' }, actor),
    /commit failed/,
  );

  assert.equal(harness.calls.updateStatus, 1);
  assert.equal(harness.calls.insertStatusLog, 1);
  assert.equal(harness.calls.insertActivityLog, 1);
  assert.equal(harness.calls.outboxInsert, 1);
  assert.equal(harness.calls.outboxDispatch, 0);
  assert.equal(harness.calls.rollback, 1);
});

test('ON_ROUTE transition enqueues TRIP_ON_ROUTE outbox event', async () => {
  const harness = createHarness({
    booking: createBooking({ status: BOOKING_STATUS.DRIVER_ASSIGNED }),
  });

  await harness.service.transition(
    'TX202607010001',
    { status: BOOKING_STATUS.ON_ROUTE },
    { id: 99, role: ROLES.DRIVER },
  );

  assert.equal(harness.records.outbox.eventType, EVENTS.TRIP_ON_ROUTE);
});

test('SETTLEMENT_PENDING transition enqueues TRIP_ENDED outbox event', async () => {
  const harness = createHarness({
    booking: createBooking({ status: BOOKING_STATUS.PICKED_UP }),
  });

  await harness.service.transition(
    'TX202607010001',
    { status: BOOKING_STATUS.SETTLEMENT_PENDING },
    { id: 99, role: ROLES.DRIVER },
  );

  assert.equal(harness.records.outbox.eventType, EVENTS.TRIP_ENDED);
});

test('COMPLETED transition closes active driver assignment', async () => {
  const harness = createHarness({
    booking: createBooking({ status: 'SETTLEMENT_PENDING' }),
  });

  const result = await harness.service.transition(
    'TX202607010001',
    { status: 'COMPLETED' },
    { id: 99, role: ROLES.ADMIN },
  );

  assert.equal(result.status, 'COMPLETED');
  assert.equal(harness.calls.completeActiveAssignment, 1);
  assert.deepEqual(harness.records.completeActiveAssignment, { bookingId: 10 });
});

test('customer can cancel DRIVER_ASSIGNED when more than 2h remain', async () => {
  const harness = createHarness({
    booking: createBooking({ status: BOOKING_STATUS.DRIVER_ASSIGNED }),
  });
  const deadlineMs = Date.parse('2026-07-25T13:00:00+07:00');

  const result = await harness.service.transition(
    'TX202607010001',
    { status: BOOKING_STATUS.CANCELLED, reason: 'CUSTOMER_CANCELLED' },
    { id: 55, role: ROLES.CUSTOMER },
    { nowMs: deadlineMs - 1000 },
  );

  assert.equal(result.status, BOOKING_STATUS.CANCELLED);
  assert.equal(harness.calls.clearAssignmentOnCancel, 1);
  assert.equal(harness.records.clearAssignmentOnCancel.reason, 'CUSTOMER_CANCELLED');
  assert.equal(harness.records.outbox.eventType, EVENTS.BOOKING_CANCELLED);
});

test('customer cannot cancel DRIVER_ASSIGNED at exact 2h deadline', async () => {
  const harness = createHarness({
    booking: createBooking({ status: BOOKING_STATUS.DRIVER_ASSIGNED }),
  });
  const deadlineMs = Date.parse('2026-07-25T13:00:00+07:00');

  await assert.rejects(
    () => harness.service.transition(
      'TX202607010001',
      { status: BOOKING_STATUS.CANCELLED },
      { id: 55, role: ROLES.CUSTOMER },
      { nowMs: deadlineMs },
    ),
    (err) => err instanceof AppError
      && err.errorCode === ERROR_CODES.INVALID_STATUS_TRANSITION
      && err.errors?.[0]?.reason === 'WITHIN_TWO_HOURS',
  );
  assert.equal(harness.calls.updateStatus, 0);
});

test('admin can force-cancel DRIVER_ASSIGNED inside 2h window', async () => {
  const harness = createHarness({
    booking: createBooking({ status: BOOKING_STATUS.DRIVER_ASSIGNED }),
  });
  const deadlineMs = Date.parse('2026-07-25T13:00:00+07:00');

  const result = await harness.service.transition(
    'TX202607010001',
    { status: BOOKING_STATUS.CANCELLED, reason: 'ADMIN_FORCE' },
    { id: 7, role: ROLES.ADMIN },
    { nowMs: deadlineMs + 60_000 },
  );

  assert.equal(result.status, BOOKING_STATUS.CANCELLED);
  assert.equal(harness.records.clearAssignmentOnCancel.reason, 'ADMIN_CANCELLED');
});

test('customer cancel via guest token clears assignment', async () => {
  const harness = createHarness({
    booking: createBooking({
      status: BOOKING_STATUS.DRIVER_ASSIGNED,
      customer_user_id: null,
    }),
  });
  const deadlineMs = Date.parse('2026-07-25T13:00:00+07:00');

  const result = await harness.service.cancelByCustomer(
    'TX202607010001',
    { guestAccessToken: 'guest-token-value' },
    null,
    { nowMs: deadlineMs - 1000 },
  );

  assert.equal(result.status, BOOKING_STATUS.CANCELLED);
  assert.equal(harness.calls.clearAssignmentOnCancel, 1);
  assert.equal(result.canCancel, false);
  assert.equal(result.cancellationBlockedReason, 'ALREADY_CANCELLED');
});

test('duplicate customer cancel is idempotent', async () => {
  const harness = createHarness({
    booking: createBooking({ status: BOOKING_STATUS.CANCELLED }),
  });

  const result = await harness.service.cancelByCustomer(
    'TX202607010001',
    { guestAccessToken: 'guest-token-value' },
    null,
  );

  assert.equal(result.status, BOOKING_STATUS.CANCELLED);
  assert.equal(result.idempotent, true);
  assert.equal(harness.calls.updateStatus, 0);
  assert.equal(harness.calls.clearAssignmentOnCancel ?? 0, 0);
});

test('customer cannot cancel ON_ROUTE even with ample time', async () => {
  const harness = createHarness({
    booking: createBooking({ status: BOOKING_STATUS.ON_ROUTE }),
  });
  const deadlineMs = Date.parse('2026-07-25T13:00:00+07:00');

  await assert.rejects(
    () => harness.service.transition(
      'TX202607010001',
      { status: BOOKING_STATUS.CANCELLED },
      { id: 55, role: ROLES.CUSTOMER },
      { nowMs: deadlineMs - 3_600_000 },
    ),
    (err) => err instanceof AppError
      && err.errorCode === ERROR_CODES.INVALID_STATUS_TRANSITION,
  );
});
