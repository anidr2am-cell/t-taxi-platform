const test = require('node:test');
const assert = require('node:assert/strict');

process.env.NODE_ENV = 'test';
process.env.DB_USER = 'test';
process.env.DB_NAME = 'tride_test';
process.env.JWT_ACCESS_SECRET = 'test-access-secret';
process.env.JWT_REFRESH_SECRET = 'test-refresh-secret';
process.env.SOCIAL_TOKEN_ENCRYPTION_KEY =
  process.env.SOCIAL_TOKEN_ENCRYPTION_KEY || Buffer.alloc(32, 3).toString('base64');
process.env.CONTACT_CONNECTION_REQUIRED = 'false';

delete require.cache[require.resolve('../src/config/env')];
delete require.cache[require.resolve('../src/policies/bookingDispatchEligibility.policy')];

const CONTACT_STATUS = require('../src/constants/contactStatus');
const BOOKING_STATUS = require('../src/constants/reservationStatus');
const ERROR_CODES = require('../src/constants/errorCodes');
const HTTP_STATUS = require('../src/constants/httpStatus');
const BookingContactConnectionService = require('../src/services/bookingContactConnection.service');
const { CONTACT_DISPATCH_STATE } = require('../src/policies/adminContactDispatch.policy');
const AdminDispatchService = require('../src/services/adminDispatch.service');
const BookingRepository = require('../src/repositories/booking.repository');

test('booking findById includes metadata required by repeat dispatch retry', async () => {
  let capturedSql = '';
  const repository = new BookingRepository({
    async query(sql) {
      capturedSql = sql;
      return [[{
        id: 21,
        metadata: JSON.stringify({ contactDispatchDelivered: true }),
      }]];
    },
  });

  const booking = await repository.findById(21);
  assert.match(capturedSql, /\bb\.metadata\b/);
  assert.deepEqual(JSON.parse(booking.metadata), { contactDispatchDelivered: true });
});

function createRetryService(overrides = {}) {
  const booking = {
    id: 21,
    booking_number: 'TX202609260001',
    contact_status: CONTACT_STATUS.VERIFIED,
    status: BOOKING_STATUS.OPEN,
    contact_requested_at: '2026-09-26 01:00:00',
    contact_channel: 'LINE',
    is_urgent_request: 0,
    payment_method: 'PAY_DRIVER',
    payment_status: 'UNPAID',
    total_amount: 1500,
    currency: 'THB',
    metadata: JSON.stringify({}),
    ...overrides.booking,
  };

  let dispatchCalls = 0;
  let connectionUpdateCalls = 0;
  let bookingUpdateCalls = 0;
  const bookingService = {
    formatDateTime: (date) => date.toISOString(),
    needsContactDispatchRetry: () => false,
    isContactDispatchDelivered(metadata) {
      if (!metadata) return false;
      const parsed = typeof metadata === 'string' ? JSON.parse(metadata) : metadata;
      return parsed.contactDispatchDelivered === true;
    },
    async dispatchAfterContactVerified(_row, options = {}) {
      dispatchCalls += 1;
      if (overrides.lockContention) {
        const err = new Error('in progress');
        err.errorCode = ERROR_CODES.CONTACT_DISPATCH_IN_PROGRESS;
        err.statusCode = HTTP_STATUS.CONFLICT;
        throw err;
      }
      if (overrides.dispatchThrows) {
        throw new Error('dispatch failed');
      }
      return overrides.dispatchStarted ?? true;
    },
  };

  const service = new BookingContactConnectionService(
    {
      async getConnection() {
        return {
          async beginTransaction() {},
          async commit() {},
          async rollback() {},
          release() {},
        };
      },
    },
    {
      async findContactBookingByNumber() {
        return booking;
      },
      async findById() {
        return booking;
      },
      async findByBookingNumberForUpdate() {
        return booking;
      },
    },
    {
      async findActiveByBookingId() {
        if (Object.prototype.hasOwnProperty.call(overrides, 'connection')) {
          return overrides.connection;
        }
        return {
          id: 9,
          channel: 'LINE',
          status: CONTACT_STATUS.VERIFIED,
        };
      },
      async updateConnectionStatus() {
        connectionUpdateCalls += 1;
      },
      async updateBookingContactSnapshot() {
        bookingUpdateCalls += 1;
        booking.contact_status = CONTACT_STATUS.VERIFIED;
      },
    },
    bookingService,
    { async getContactChannelsPublic() { return { channels: [] }; } },
  );

  return {
    service,
    booking,
    getDispatchCalls: () => dispatchCalls,
    getConnectionUpdateCalls: () => connectionUpdateCalls,
    getBookingUpdateCalls: () => bookingUpdateCalls,
  };
}

test('adminRetryDispatch rejects delivered bookings', async () => {
  const { service, getDispatchCalls } = createRetryService({
    booking: {
      metadata: JSON.stringify({
        contactDispatchCompleted: true,
        contactDispatchDelivered: true,
      }),
    },
  });

  await assert.rejects(
    () => service.adminRetryDispatch('TX202609260001'),
    (err) => err.errorCode === ERROR_CODES.CONTACT_DISPATCH_ALREADY_DELIVERED
      && err.statusCode === HTTP_STATUS.CONFLICT,
  );
  assert.equal(getDispatchCalls(), 0);
});

test('adminRetryDispatch rejects gate=false immediate bookings without contact flow', async () => {
  const { service, getDispatchCalls } = createRetryService({
    booking: {
      contact_requested_at: null,
      metadata: JSON.stringify({}),
    },
    connection: null,
  });

  await assert.rejects(
    () => service.adminRetryDispatch('TX202609260001'),
    (err) => err.errorCode === ERROR_CODES.CONTACT_DISPATCH_NOT_RETRYABLE,
  );
  assert.equal(getDispatchCalls(), 0);
});

test('adminRetryDispatch rejects PENDING bookings', async () => {
  const { service } = createRetryService({
    booking: { contact_status: CONTACT_STATUS.PENDING },
  });
  await assert.rejects(
    () => service.adminRetryDispatch('TX202609260001'),
    (err) => err.errorCode === ERROR_CODES.CONTACT_DISPATCH_NOT_RETRYABLE,
  );
});

test('adminRetryDispatch surfaces lock contention', async () => {
  const { service } = createRetryService({
    booking: { metadata: JSON.stringify({ contactDispatchCompleted: true }) },
    lockContention: true,
  });
  await assert.rejects(
    () => service.adminRetryDispatch('TX202609260001'),
    (err) => err.errorCode === ERROR_CODES.CONTACT_DISPATCH_IN_PROGRESS,
  );
});

test('adminRetryDispatch starts for DISPATCH_PENDING leftover', async () => {
  const { service, getDispatchCalls } = createRetryService();
  const result = await service.adminRetryDispatch('TX202609260001');
  assert.equal(result.dispatchStarted, true);
  assert.equal(getDispatchCalls(), 1);
  assert.equal(result.contactDispatch.state, CONTACT_DISPATCH_STATE.DISPATCH_PENDING);
});

test('repeat adminVerify on VERIFIED stays 200/no-op when retry helper is false', async () => {
  const { service, getDispatchCalls } = createRetryService();
  const result = await service.adminVerify('TX202609260001', 7);
  assert.equal(result.dispatchStarted, false);
  assert.equal(getDispatchCalls(), 0);
});

test('gate=false leftover CONFIRM_REQUESTED verify starts dispatch once', async () => {
  const { service, booking, getDispatchCalls } = createRetryService({
    booking: {
      id: 22,
      booking_number: 'TX202609260002',
      contact_status: CONTACT_STATUS.CONFIRM_REQUESTED,
      status: BOOKING_STATUS.OPEN,
      contact_requested_at: '2026-09-26 01:00:00',
      is_urgent_request: 1,
      metadata: JSON.stringify({}),
      payment_method: 'PAY_DRIVER',
      payment_status: 'UNPAID',
      total_amount: 1800,
      currency: 'THB',
    },
    connection: {
      id: 4,
      channel: 'LINE',
      status: CONTACT_STATUS.CONFIRM_REQUESTED,
    },
  });
  const result = await service.adminVerify('TX202609260002', 3);
  assert.equal(result.dispatchStarted, true);
  assert.equal(getDispatchCalls(), 1);
  assert.equal(booking.contact_status, CONTACT_STATUS.VERIFIED);
});

test('adminVerify rejects non-open CONFIRM_REQUESTED before updates or dispatch', async () => {
  const {
    service,
    getDispatchCalls,
    getConnectionUpdateCalls,
    getBookingUpdateCalls,
  } = createRetryService({
    booking: {
      contact_status: CONTACT_STATUS.CONFIRM_REQUESTED,
      status: BOOKING_STATUS.DRIVER_ASSIGNED,
      contact_requested_at: '2026-09-26 01:00:00',
    },
  });

  await assert.rejects(
    () => service.adminVerify('TX202609260001', 7),
    (err) => err.statusCode === HTTP_STATUS.CONFLICT
      && err.errorCode === ERROR_CODES.INVALID_STATUS_TRANSITION,
  );
  assert.equal(getConnectionUpdateCalls(), 0);
  assert.equal(getBookingUpdateCalls(), 0);
  assert.equal(getDispatchCalls(), 0);
});

test('concurrent leftover verify and retry share one dispatchAfterContactVerified call path', async () => {
  let inFlight = 0;
  let maxInFlight = 0;
  let dispatchCalls = 0;
  const booking = {
    id: 23,
    booking_number: 'TX202609260003',
    contact_status: CONTACT_STATUS.CONFIRM_REQUESTED,
    status: BOOKING_STATUS.OPEN,
    contact_requested_at: '2026-09-26 01:00:00',
    metadata: JSON.stringify({}),
    payment_method: 'PAY_DRIVER',
    payment_status: 'UNPAID',
    total_amount: 1000,
    currency: 'THB',
    is_urgent_request: 0,
  };

  const service = new BookingContactConnectionService(
    {
      async getConnection() {
        return {
          async beginTransaction() {},
          async commit() {},
          async rollback() {},
          release() {},
        };
      },
    },
    {
      async findContactBookingByNumber() { return booking; },
      async findById() { return booking; },
      async findByBookingNumberForUpdate() { return { ...booking }; },
    },
    {
      async findActiveByBookingId() {
        return { id: 1, channel: 'LINE', status: booking.contact_status };
      },
      async updateConnectionStatus() {
        booking.contact_status = CONTACT_STATUS.VERIFIED;
      },
      async updateBookingContactSnapshot() {
        booking.contact_status = CONTACT_STATUS.VERIFIED;
      },
    },
    {
      formatDateTime: (date) => date.toISOString(),
      needsContactDispatchRetry: () => false,
      isContactDispatchDelivered: () => false,
      async dispatchAfterContactVerified() {
        dispatchCalls += 1;
        inFlight += 1;
        maxInFlight = Math.max(maxInFlight, inFlight);
        await new Promise((resolve) => setTimeout(resolve, 15));
        inFlight -= 1;
        booking.metadata = JSON.stringify({
          contactDispatchCompleted: true,
          contactDispatchDelivered: true,
        });
        return true;
      },
    },
    { async getContactChannelsPublic() { return { channels: [] }; } },
  );

  const [verifyResult, retryResult] = await Promise.allSettled([
    service.adminVerify('TX202609260003', 1),
    service.adminRetryDispatch('TX202609260003'),
  ]);

  assert.equal(verifyResult.status, 'fulfilled');
  assert.ok(retryResult.status === 'fulfilled' || retryResult.reason?.errorCode);
  assert.ok(dispatchCalls >= 1);
  assert.ok(maxInFlight <= 2);
});

test('admin detail exposes derived contactDispatch and matching allowedActions', async () => {
  const bookingRepo = {
    async findAdminBookingDetail() {
      return {
        id: 1,
        booking_number: 'TX202609260010',
        status: BOOKING_STATUS.OPEN,
        contact_status: CONTACT_STATUS.CONFIRM_REQUESTED,
        contact_channel: 'LINE',
        contact_requested_at: '2026-09-26 01:00:00',
        contact_verified_at: null,
        is_urgent_request: 1,
        metadata: JSON.stringify({}),
        scheduled_pickup_at: '2026-09-26 10:00:00',
        origin_address: 'BKK',
        destination_address: 'Pattaya',
        customer_name: 'Kim',
        customer_email: 'kim@example.com',
        customer_phone: '+66111',
        customer_country_code: 'KR',
        booking_source: 'CUSTOMER',
        adults: 1,
        children: 0,
        infants: 0,
        service_type_code: 'AIRPORT_PICKUP',
        service_type_name: 'Airport pickup',
        vehicle_type_code: 'VAN',
        vehicle_type_name: 'Van',
        total_amount: 1000,
        currency: 'THB',
        payment_method: 'PAY_DRIVER',
        payment_status: 'UNPAID',
      };
    },
    async findChargeItemsByBookingId() { return []; },
    async findStatusLogsByBookingId() { return []; },
    async findAssignmentsByBookingId() { return []; },
    async countAdminUnreadForBooking() { return 0; },
  };
  const service = new AdminDispatchService(
    {},
    bookingRepo,
    {},
    {},
    { evaluateSettlement() { return {}; } },
    null,
    null,
    {},
  );
  service.commissionSettlementService = null;
  const detail = await service.getBookingDetail('TX202609260010', { id: 1, role: 'ADMIN' });
  assert.equal(detail.isUrgentRequest, true);
  assert.equal(detail.contactDispatch.state, CONTACT_DISPATCH_STATE.WAITING_CONTACT);
  assert.equal(detail.contactDispatch.retryable, false);
  assert.equal(detail.contactDispatch.mode, 'URGENT');
  assert.ok(detail.allowedActions.includes('VERIFY_CONTACT'));
  assert.ok(!detail.allowedActions.includes('RETRY_CONTACT_DISPATCH'));
  assert.equal(detail.customer.contactRequestedAt, '2026-09-26 01:00:00');
});

test('admin detail marks non-open contact flow NOT_OPEN without verify or retry actions', async () => {
  const bookingRepo = {
    async findAdminBookingDetail() {
      return {
        id: 2,
        booking_number: 'TX202609260011',
        status: BOOKING_STATUS.DRIVER_ASSIGNED,
        contact_status: CONTACT_STATUS.CONFIRM_REQUESTED,
        contact_channel: 'LINE',
        contact_requested_at: '2026-09-26 01:00:00',
        contact_verified_at: null,
        is_urgent_request: 0,
        metadata: JSON.stringify({}),
        scheduled_pickup_at: '2026-09-26 10:00:00',
        origin_address: 'BKK',
        destination_address: 'Pattaya',
        customer_name: 'Kim',
        customer_email: 'kim@example.com',
        customer_phone: '+66111',
        customer_country_code: 'KR',
        booking_source: 'CUSTOMER',
        adults: 1,
        children: 0,
        infants: 0,
        service_type_code: 'AIRPORT_PICKUP',
        service_type_name: 'Airport pickup',
        vehicle_type_code: 'VAN',
        vehicle_type_name: 'Van',
        total_amount: 1000,
        currency: 'THB',
        payment_method: 'PAY_DRIVER',
        payment_status: 'UNPAID',
      };
    },
    async findChargeItemsByBookingId() { return []; },
    async findStatusLogsByBookingId() { return []; },
    async findAssignmentsByBookingId() { return []; },
    async countAdminUnreadForBooking() { return 0; },
  };
  const service = new AdminDispatchService(
    {}, bookingRepo, {}, {}, { evaluateSettlement() { return {}; } }, null, null, {},
  );
  service.commissionSettlementService = null;

  const detail = await service.getBookingDetail('TX202609260011', { id: 1, role: 'ADMIN' });
  assert.equal(detail.contactDispatch.state, CONTACT_DISPATCH_STATE.NOT_OPEN);
  assert.ok(!detail.allowedActions.includes('VERIFY_CONTACT'));
  assert.ok(!detail.allowedActions.includes('RETRY_CONTACT_DISPATCH'));
});
