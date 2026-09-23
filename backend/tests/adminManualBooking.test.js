const test = require('node:test');
const assert = require('node:assert/strict');

process.env.NODE_ENV = process.env.NODE_ENV || 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'tride_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret';
process.env.SOCIAL_TOKEN_ENCRYPTION_KEY = process.env.SOCIAL_TOKEN_ENCRYPTION_KEY
  || Buffer.alloc(32, 1).toString('base64');

const BookingService = require('../src/services/booking.service');
const BOOKING_STATUS = require('../src/constants/reservationStatus');
const NOTIFICATION_TYPES = require('../src/constants/notificationTypes');
const { EVENTS } = require('../src/events');
const { driverUserRoom, setRealtimeIo } = require('../src/socket/realtime');

const ADMIN = { id: 1, role: 'ADMIN' };

function createHarness({ customerUserId = null, customerChargeAmount = null } = {}) {
  const calls = {
    booking: null,
    chargeItems: [],
    notifications: [],
    notes: [],
    socket: [],
    outbox: [],
    dispatchedOutboxIds: [],
    commits: 0,
    rollbacks: 0,
  };
  const conn = {
    async beginTransaction() {},
    async commit() { calls.commits += 1; },
    async rollback() { calls.rollbacks += 1; },
    release() {},
  };
  const bookingRepository = {
    async insertBooking(_conn, row) {
      calls.booking = row;
      return 10;
    },
    async insertPassengers() {},
    async insertLuggage() {},
    async insertChargeItem(_conn, _bookingId, item) {
      calls.chargeItems.push(item);
    },
    async insertStatusLog() {},
    async insertActivityLog() {},
    async findById() {
      return {
        id: 10,
        booking_number: 'TX202607130001',
        status: BOOKING_STATUS.OPEN,
        payment_status: calls.booking?.paymentMethod === 'ADMIN_COLLECTED' ? 'PAID' : 'UNPAID',
        total_amount: calls.chargeItems[0]?.amount ?? 0,
        currency: 'THB',
      };
    },
    async findByBookingNumberForUpdate(_conn, bookingNumber) {
      return {
        id: 10,
        booking_number: bookingNumber,
        status: BOOKING_STATUS.OPEN,
        booking_source: 'ADMIN_MANUAL',
      };
    },
    async findBookingMetadataForUpdate() {
      return null;
    },
    async updateAdminManualBookingFields() {},
    async updatePassengers() {},
    async upsertManualPayoutChargeItem(_conn, _bookingId, item) {
      calls.chargeItems = [item];
    },
    async syncAdminManualNameSignChargeItem(_conn, _bookingId, enabled) {
      if (enabled) {
        calls.chargeItems.push({
          chargeType: 'NAME_SIGN',
          amount: 0,
        });
      }
    },
  };
  const couponRepository = {
    async findCustomerById(id) {
      if (id !== 55) return null;
      return {
        id: 55,
        role: 'CUSTOMER',
        name: 'Member Kim',
        phone: '0811111111',
        email: 'kim@example.com',
      };
    },
  };
  const noteService = {
    async create(bookingNumber, payload, adminUser) {
      calls.notes.push({ bookingNumber, payload, adminUser });
    },
  };
  const containerPath = require.resolve('../src/helpers/container');
  const originalContainer = require(containerPath);
  require.cache[containerPath].exports = {
    ...originalContainer,
    get(name) {
      if (name === 'adminBookingNoteService') return noteService;
      return originalContainer.get(name);
    },
  };

  const service = new BookingService(
    { async getConnection() { return conn; } },
    bookingRepository,
    { async generateNext() { return 'TX202607130001'; } },
    {
      async resolveServiceType() {
        return { id: 2, code: 'CITY_TRANSFER', name: 'City transfer' };
      },
    },
    { async recommend() { return { recommendedVehicle: 'SEDAN' }; } },
    { async findTypeByCode() { return { id: 1, code: 'SEDAN', name: 'Sedan' }; } },
    {
      async insertNotificationEvent(_conn, event) {
        calls.outbox.push(event);
        return 30;
      },
    },
    {
      async dispatchOutboxIds(ids) {
        calls.dispatchedOutboxIds.push(ids);
      },
    },
    null,
    {
      async listEligibleForOpenBooking() {
        return [{ id: 7, user_id: 42 }];
      },
    },
    () => ({
      async sendDirectNotification(notification) {
        calls.notifications.push(notification);
      },
    }),
    null,
    null,
    null,
    null,
    { couponRepository },
  );

  setRealtimeIo({
    to(room) {
      return {
        emit(event, payload) {
          calls.socket.push({ room, event, payload });
        },
      };
    },
  });

  const input = {
    origin: { address: 'Suvarnabhumi Airport' },
    destination: { address: 'Pattaya Beach' },
    scheduledPickupAt: '2026-12-01T02:30:00.000Z',
    vehicleTypeCode: 'SEDAN',
    payoutAmount: 800,
    paymentCollection: customerUserId ? 'DRIVER_COLLECTS' : 'ADMIN_COLLECTED',
    customer: customerUserId
      ? { customerUserId, name: 'Ignored', phone: '000' }
      : { name: 'Guest Lee', phone: '0822222222' },
    customerChargeAmount,
  };

  return {
    service,
    calls,
    input,
    restoreContainer() {
      require.cache[containerPath].exports = originalContainer;
    },
  };
}

test('createAdminManualBooking links member, marks commission exempt, and broadcasts open call', async () => {
  const { service, calls, input, restoreContainer } = createHarness({ customerUserId: 55 });
  try {
    const result = await service.createAdminManualBooking(input, ADMIN);

    assert.equal(calls.booking.bookingSource, 'ADMIN_MANUAL');
    assert.equal(calls.booking.commissionExempt, true);
    assert.equal(calls.booking.customerUserId, 55);
    assert.equal(calls.booking.customerName, 'Member Kim');
    assert.equal(calls.booking.contactStatus, 'VERIFIED');
    assert.equal(calls.booking.paymentMethod, 'PAY_DRIVER');
    assert.equal(calls.chargeItems[0].amount, 800);
    assert.equal(result.bookingNumber, 'TX202607130001');
    assert.equal(calls.commits, 1);
    assert.equal(calls.notifications.length, 1);
    assert.equal(
      calls.notifications[0].notificationType,
      NOTIFICATION_TYPES.DRIVER_CALL_AVAILABLE,
    );
    assert.equal(calls.socket[0].payload.isAdminManualCall, true);
    assert.equal(calls.socket[0].payload.requiresBankAccountConfirmation, false);
    assert.equal(calls.notes.length, 0);
    assert.equal(calls.outbox.length, 1);
    assert.equal(calls.outbox[0].eventType, EVENTS.BOOKING_CREATED);
    assert.equal(calls.outbox[0].payload.customerUserId, 55);
    assert.deepEqual(calls.dispatchedOutboxIds, [[30]]);
  } finally {
    setRealtimeIo(null);
    restoreContainer();
  }
});

test('createAdminManualBooking marks name sign for drivers when picket enabled', async () => {
  const { service, calls, input, restoreContainer } = createHarness({ customerUserId: 55 });
  try {
    await service.createAdminManualBooking(
      {
        ...input,
        nameSign: true,
        nameSignText: 'KIM MINSU',
      },
      ADMIN,
    );

    assert.equal(calls.booking.nameSignText, 'KIM MINSU');
    assert.equal(
      calls.chargeItems.some((item) => item.chargeType === 'NAME_SIGN'),
      true,
    );
    assert.equal(calls.socket[0].payload.nameSignRequested, true);
    assert.equal(calls.socket[0].payload.nameSignText, 'KIM MINSU');
  } finally {
    setRealtimeIo(null);
    restoreContainer();
  }
});

test('updateAdminManualBooking updates payout for admin manual open call', async () => {
  const { service, calls, input, restoreContainer } = createHarness({ customerUserId: 55 });
  try {
    const result = await service.updateAdminManualBooking(
      'TX202607130001',
      { ...input, payoutAmount: 950 },
      ADMIN,
    );

    assert.equal(result.bookingNumber, 'TX202607130001');
    assert.equal(calls.chargeItems[0].amount, 950);
    assert.equal(calls.commits, 1);
  } finally {
    restoreContainer();
  }
});

test('createAdminManualBooking creates guest booking and auto note when customer charge provided', async () => {
  const { service, calls, input, restoreContainer } = createHarness({
    customerChargeAmount: 1000,
  });
  try {
    await service.createAdminManualBooking(input, ADMIN);

    assert.equal(calls.booking.customerUserId, null);
    assert.equal(calls.booking.customerName, 'Guest Lee');
    assert.equal(calls.booking.paymentMethod, 'ADMIN_COLLECTED');
    assert.equal(calls.socket[0].payload.requiresBankAccountConfirmation, true);
    assert.equal(calls.notes.length, 1);
    assert.match(calls.notes[0].payload.text, /고객 결제 1000 THB/);
    assert.match(calls.notes[0].payload.text, /기사 지급 800 THB/);
    assert.equal(calls.outbox.length, 1);
    assert.equal(calls.outbox[0].eventType, EVENTS.BOOKING_CREATED);
    assert.equal(calls.outbox[0].payload.customerUserId, null);
    assert.deepEqual(calls.dispatchedOutboxIds, [[30]]);
  } finally {
    setRealtimeIo(null);
    restoreContainer();
  }
});
