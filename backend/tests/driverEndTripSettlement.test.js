process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const { test } = require('node:test');
const assert = require('node:assert/strict');

const BookingStatusService = require('../src/services/bookingStatus.service');
const DriverTripFlowService = require('../src/services/driverTripFlow.service');
const DriverJobService = require('../src/services/driverJob.service');
const NotificationService = require('../src/services/notification.service');
const AppError = require('../src/utils/AppError');
const ERROR_CODES = require('../src/constants/errorCodes');
const ROLES = require('../src/constants/roles');
const BOOKING_STATUS = require('../src/constants/reservationStatus');
const NOTIFICATION_TYPES = require('../src/constants/notificationTypes');
const { EVENTS } = require('../src/events');

const DRIVER_USER_ID = 44;
const OTHER_DRIVER_USER_ID = 55;
const BOOKING_NUMBER = 'TX202607010001';

function createBooking(overrides = {}) {
  return {
    id: 10,
    booking_number: BOOKING_NUMBER,
    status: BOOKING_STATUS.PICKED_UP,
    total_amount: '1600.00',
    currency: 'THB',
    payment_status: 'UNPAID',
    payment_method: 'PAY_DRIVER',
    customer_user_id: null,
    driver_id: 5,
    driver_user_id: DRIVER_USER_ID,
    commission_status: 'NOT_DUE_YET',
    commission_amount: null,
    commission_receipt_file_id: null,
    ...overrides,
  };
}

function createEndTripHarness(initialBooking = createBooking()) {
  const calls = {
    commissionUpdates: 0,
    outboxInserts: 0,
    statusLogs: 0,
    outboxDispatch: 0,
  };
  const outboxEvents = [];
  const statusLogs = [];
  let booking = { ...initialBooking };

  const conn = {
    async beginTransaction() {},
    async commit() {},
    async rollback() {},
    release() {},
  };
  const pool = { async getConnection() { return conn; } };

  const bookingRepository = {
    async findByBookingNumberForUpdate() {
      return { ...booking };
    },
    async findActiveDriverBookingByNumberForUpdate(_c, driverUserId, bookingNumber) {
      if (bookingNumber !== BOOKING_NUMBER) return null;
      if (driverUserId !== booking.driver_user_id) return null;
      return { booking_number: booking.booking_number, status: booking.status };
    },
    async updateStatus(_c, bookingId, status) {
      booking = { ...booking, status };
    },
    async updateCommissionFields(_c, bookingId, fields) {
      calls.commissionUpdates += 1;
      booking = {
        ...booking,
        commission_status: fields.commissionStatus ?? booking.commission_status,
        commission_amount: fields.commissionAmount ?? booking.commission_amount,
        commission_receipt_file_id: fields.commissionReceiptFileId
          ?? booking.commission_receipt_file_id,
      };
    },
    async insertStatusLog(_c, bookingId, log) {
      calls.statusLogs += 1;
      statusLogs.push(log);
    },
    async insertActivityLog() {},
    async completeActiveAssignment() {},
  };

  const outboxRepository = {
    async insertNotificationEvent(_c, data) {
      calls.outboxInserts += 1;
      outboxEvents.push(data);
      return calls.outboxInserts;
    },
  };

  const outboxProcessor = {
    async dispatchOutboxIds(ids) {
      calls.outboxDispatch += 1;
    },
  };

  const bookingStatusService = new BookingStatusService(
    pool,
    bookingRepository,
    outboxRepository,
    outboxProcessor,
  );
  const driverJobService = new DriverJobService(bookingRepository);
  const driverTripFlowService = new DriverTripFlowService(
    pool,
    bookingRepository,
    bookingStatusService,
    driverJobService,
  );

  return {
    calls,
    outboxEvents,
    statusLogs,
    get booking() { return { ...booking }; },
    driverTripFlowService,
    bookingStatusService,
    bookingRepository,
  };
}

test('endTrip moves PICKED_UP to SETTLEMENT_PENDING with 200 THB commission', async () => {
  const harness = createEndTripHarness();

  const result = await harness.driverTripFlowService.endTrip(DRIVER_USER_ID, BOOKING_NUMBER);

  assert.equal(result.status, BOOKING_STATUS.SETTLEMENT_PENDING);
  assert.equal(harness.booking.status, BOOKING_STATUS.SETTLEMENT_PENDING);
  assert.equal(harness.calls.commissionUpdates, 1);
  assert.equal(harness.booking.commission_amount, 200);
  assert.equal(harness.booking.commission_status, 'DUE');
  assert.equal(harness.calls.statusLogs, 1);
  assert.equal(harness.calls.outboxInserts, 1);
  assert.equal(harness.outboxEvents[0].eventType, EVENTS.TRIP_ENDED);
  assert.equal(harness.outboxEvents[0].payload.bookingNumber, BOOKING_NUMBER);
});

test('repeated endTrip is idempotent and keeps single commission update', async () => {
  const harness = createEndTripHarness();

  await harness.driverTripFlowService.endTrip(DRIVER_USER_ID, BOOKING_NUMBER);
  const firstCommissionUpdates = harness.calls.commissionUpdates;
  const firstOutbox = harness.calls.outboxInserts;

  const second = await harness.driverTripFlowService.endTrip(DRIVER_USER_ID, BOOKING_NUMBER);

  assert.equal(second.status, BOOKING_STATUS.SETTLEMENT_PENDING);
  assert.equal(second.idempotent, true);
  assert.equal(harness.calls.commissionUpdates, firstCommissionUpdates);
  assert.equal(harness.calls.outboxInserts, firstOutbox);
  assert.equal(harness.calls.statusLogs, 1);
  assert.equal(harness.booking.commission_amount, 200);
});

test('repeated endTrip preserves existing receipt metadata', async () => {
  const harness = createEndTripHarness(createBooking({
    status: BOOKING_STATUS.SETTLEMENT_PENDING,
    commission_status: 'RECEIPT_SUBMITTED',
    commission_amount: 200,
    commission_receipt_file_id: 42,
  }));

  const result = await harness.driverTripFlowService.endTrip(DRIVER_USER_ID, BOOKING_NUMBER);

  assert.equal(result.idempotent, true);
  assert.equal(harness.calls.commissionUpdates, 0);
  assert.equal(harness.booking.commission_receipt_file_id, 42);
  assert.equal(harness.booking.commission_status, 'RECEIPT_SUBMITTED');
});

test('other driver endTrip is rejected without state change', async () => {
  const harness = createEndTripHarness();

  await assert.rejects(
    () => harness.driverTripFlowService.endTrip(OTHER_DRIVER_USER_ID, BOOKING_NUMBER),
    (err) => err.errorCode === ERROR_CODES.BOOKING_NOT_FOUND,
  );

  assert.equal(harness.booking.status, BOOKING_STATUS.PICKED_UP);
  assert.equal(harness.calls.commissionUpdates, 0);
  assert.equal(harness.calls.outboxInserts, 0);
});

test('endTrip from DRIVER_ASSIGNED is rejected', async () => {
  const harness = createEndTripHarness(createBooking({ status: BOOKING_STATUS.DRIVER_ASSIGNED }));

  await assert.rejects(
    () => harness.driverTripFlowService.endTrip(DRIVER_USER_ID, BOOKING_NUMBER),
    (err) => err instanceof AppError && err.errorCode === ERROR_CODES.INVALID_STATUS_TRANSITION,
  );

  assert.equal(harness.booking.status, BOOKING_STATUS.DRIVER_ASSIGNED);
  assert.equal(harness.calls.commissionUpdates, 0);
});

test('endTrip from ON_ROUTE is rejected', async () => {
  const harness = createEndTripHarness(createBooking({ status: BOOKING_STATUS.ON_ROUTE }));

  await assert.rejects(
    () => harness.driverTripFlowService.endTrip(DRIVER_USER_ID, BOOKING_NUMBER),
    (err) => err.errorCode === ERROR_CODES.INVALID_STATUS_TRANSITION,
  );
});

test('endTrip from DRIVER_ARRIVED is rejected', async () => {
  const harness = createEndTripHarness(createBooking({ status: BOOKING_STATUS.DRIVER_ARRIVED }));

  await assert.rejects(
    () => harness.driverTripFlowService.endTrip(DRIVER_USER_ID, BOOKING_NUMBER),
    (err) => err.errorCode === ERROR_CODES.INVALID_STATUS_TRANSITION,
  );
});

test('trip status transitions enqueue customer notification events once', async () => {
  const harness = createEndTripHarness(createBooking({ status: BOOKING_STATUS.DRIVER_ASSIGNED }));

  await harness.bookingStatusService.transition(
    BOOKING_NUMBER,
    { status: BOOKING_STATUS.ON_ROUTE },
    { id: DRIVER_USER_ID, role: ROLES.DRIVER },
  );
  assert.equal(harness.outboxEvents.at(-1).eventType, EVENTS.TRIP_ON_ROUTE);

  await harness.bookingStatusService.transition(
    BOOKING_NUMBER,
    { status: BOOKING_STATUS.DRIVER_ARRIVED },
    { id: DRIVER_USER_ID, role: ROLES.DRIVER },
  );
  assert.equal(harness.outboxEvents.at(-1).eventType, EVENTS.DRIVER_ARRIVED);

  await harness.bookingStatusService.transition(
    BOOKING_NUMBER,
    { status: BOOKING_STATUS.PICKED_UP },
    { id: DRIVER_USER_ID, role: ROLES.DRIVER },
  );
  assert.equal(harness.outboxEvents.at(-1).eventType, EVENTS.TRIP_PICKED_UP);

  const beforeEnd = harness.calls.outboxInserts;
  await harness.driverTripFlowService.endTrip(DRIVER_USER_ID, BOOKING_NUMBER);
  assert.equal(harness.calls.outboxInserts, beforeEnd + 1);
  assert.equal(harness.outboxEvents.at(-1).eventType, EVENTS.TRIP_ENDED);

  const duplicate = await harness.driverTripFlowService.endTrip(DRIVER_USER_ID, BOOKING_NUMBER);
  assert.equal(duplicate.idempotent, true);
  assert.equal(harness.calls.outboxInserts, beforeEnd + 1);
});

test('TRIP_ENDED notification copy avoids settlement wording', async () => {
  const bookingRepository = {
    async findById() {
      return { id: 10, booking_number: BOOKING_NUMBER, customer_user_id: null };
    },
  };
  const service = new NotificationService({}, {}, {}, bookingRepository, {}, {});
  const content = service.resolveContent(
    NOTIFICATION_TYPES.TRIP_ENDED,
    BOOKING_NUMBER,
  );

  assert.equal(content.body.toLowerCase().includes('settlement'), false);
  assert.equal(content.title.toLowerCase().includes('settlement'), false);
  assert.match(content.body, /Thank you for riding with us/);

  const specs = await service.buildSpecsForEvent(EVENTS.TRIP_ENDED, {
    eventId: 'evt-trip-ended',
    bookingId: 10,
    bookingNumber: BOOKING_NUMBER,
  });
  assert.equal(specs.length, 1);
  assert.equal(specs[0].notificationType, NOTIFICATION_TYPES.TRIP_ENDED);
  assert.equal(specs[0].bookingId, 10);
});

test('TRIP_ON_ROUTE notification maps to customer spec', async () => {
  const bookingRepository = {
    async findById() {
      return { id: 10, booking_number: BOOKING_NUMBER, customer_user_id: null };
    },
  };
  const service = new NotificationService({}, {}, {}, bookingRepository, {}, {});
  const specs = await service.buildSpecsForEvent(EVENTS.TRIP_ON_ROUTE, {
    eventId: 'evt-on-route',
    bookingId: 10,
    bookingNumber: BOOKING_NUMBER,
  });
  assert.equal(specs.length, 1);
  assert.equal(specs[0].notificationType, NOTIFICATION_TYPES.TRIP_ON_ROUTE);

  const content = service.resolveContent(NOTIFICATION_TYPES.TRIP_ON_ROUTE, BOOKING_NUMBER);
  assert.match(content.body, /pickup location/);
});
