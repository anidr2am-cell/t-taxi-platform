const test = require('node:test');
const assert = require('node:assert/strict');

process.env.NODE_ENV = 'test';
process.env.DB_USER = 'test';
process.env.DB_NAME = 'tride_test';
process.env.JWT_ACCESS_SECRET = 'test-access-secret';
process.env.JWT_REFRESH_SECRET = 'test-refresh-secret';

const CONTACT_STATUS = require('../src/constants/contactStatus');
const BOOKING_STATUS = require('../src/constants/reservationStatus');
const BookingContactConnectionService = require('../src/services/bookingContactConnection.service');

function createService(overrides = {}) {
  let lockQueue = Promise.resolve();
  const pool = {
    async getConnection() {
      return {
        async beginTransaction() {},
        async commit() {},
        async rollback() {},
        release() {},
      };
    },
  };

  const bookingRepository = {
    async findByBookingNumberForUpdate(_conn, _bookingNumber) {
      return overrides.booking ?? null;
    },
    async findById(id) {
      return overrides.bookingById ?? { ...(overrides.booking ?? {}), id };
    },
    async findContactBookingByNumber() {
      return overrides.refreshedBooking ?? overrides.booking ?? null;
    },
  };

  const contactConnectionRepository = {
    async findActiveByBookingId() {
      return overrides.connection ?? null;
    },
    async findById(_conn, connectionId) {
      return overrides.connection ?? {
        id: connectionId,
        channel: 'WHATSAPP',
        status: CONTACT_STATUS.PENDING,
      };
    },
    async updateConnectionStatus() {},
    async updateBookingContactSnapshot() {},
    async insertConnection() {
      return 1;
    },
    async cancelActiveConnections() {},
  };

  let dispatchCalls = 0;
  const bookingService = {
    async assertCustomerOrGuestAccess() {},
    formatDateTime: (date) => date.toISOString(),
    needsContactDispatchRetry(booking) {
      if (overrides.needsContactDispatchRetry) {
        return overrides.needsContactDispatchRetry(booking);
      }
      return false;
    },
    async dispatchAfterContactVerified() {
      dispatchCalls += 1;
      if (overrides.dispatchThrows) {
        throw new Error('dispatch failed');
      }
      return true;
    },
    get dispatchCalls() {
      return dispatchCalls;
    },
  };

  const platformSettingsService = {
    async getContactChannelsPublic() {
      return {
        channels: overrides.enabledChannels ?? [
          { code: 'LINE', enabled: true },
          { code: 'WHATSAPP', enabled: true },
        ],
      };
    },
  };

  const service = new BookingContactConnectionService(
    pool,
    bookingRepository,
    contactConnectionRepository,
    bookingService,
    platformSettingsService,
  );

  return { service, bookingService, getDispatchCalls: () => dispatchCalls };
}

test('startConnection rejects disabled channel', async () => {
  const previous = process.env.CONTACT_CONNECTION_REQUIRED;
  process.env.CONTACT_CONNECTION_REQUIRED = 'true';
  delete require.cache[require.resolve('../src/config/env')];
  delete require.cache[require.resolve('../src/policies/bookingDispatchEligibility.policy')];

  const { service } = createService({
    booking: {
      id: 1,
      booking_number: 'TX202608130001',
      contact_status: CONTACT_STATUS.PENDING,
      status: BOOKING_STATUS.OPEN,
    },
    enabledChannels: [{ code: 'WHATSAPP', enabled: true }],
  });

  await assert.rejects(
    () => service.startConnection('TX202608130001', 'LINE', null, 'guest-token'),
    (err) => err.message === 'Contact channel is not available',
  );

  process.env.CONTACT_CONNECTION_REQUIRED = previous;
  delete require.cache[require.resolve('../src/config/env')];
  delete require.cache[require.resolve('../src/policies/bookingDispatchEligibility.policy')];
});

test('startConnection passes transaction conn as first arg to findByBookingNumberForUpdate', async () => {
  let capturedConn = null;
  let capturedBookingNumber = null;

  const pool = {
    async getConnection() {
      const conn = {
        async beginTransaction() {},
        async commit() {},
        async rollback() {},
        release() {},
      };
      return conn;
    },
  };

  const bookingRepository = {
    async findByBookingNumberForUpdate(conn, bookingNumber) {
      capturedConn = conn;
      capturedBookingNumber = bookingNumber;
      return {
        id: 1,
        booking_number: bookingNumber,
        contact_status: CONTACT_STATUS.PENDING,
        status: BOOKING_STATUS.OPEN,
        is_urgent_request: 0,
        payment_method: 'PAY_DRIVER',
        payment_status: 'UNPAID',
        total_amount: 1000,
        currency: 'THB',
      };
    },
    async findById(id) {
      return {
        id,
        booking_number: capturedBookingNumber,
        contact_status: CONTACT_STATUS.PENDING,
        status: BOOKING_STATUS.OPEN,
        is_urgent_request: 0,
        payment_method: 'PAY_DRIVER',
        payment_status: 'UNPAID',
        total_amount: 1000,
        currency: 'THB',
      };
    },
    async findContactBookingByNumber() {
      return null;
    },
  };

  const contactConnectionRepository = {
    async cancelActiveConnections() {},
    async insertConnection() {
      return 1;
    },
    async updateBookingContactSnapshot() {},
    async findById(_conn, connectionId) {
      return {
        id: connectionId,
        channel: 'LINE',
        status: CONTACT_STATUS.PENDING,
      };
    },
  };

  const service = new BookingContactConnectionService(
    pool,
    bookingRepository,
    contactConnectionRepository,
    { async assertCustomerOrGuestAccess() {}, formatDateTime: (d) => d.toISOString() },
    {
      async getContactChannelsPublic() {
        return { channels: [{ code: 'LINE', enabled: true }] };
      },
    },
  );

  await service.startConnection('TX202608130001', 'LINE', null, 'guest-token');

  assert.equal(typeof capturedConn?.beginTransaction, 'function');
  assert.equal(capturedBookingNumber, 'TX202608130001');
});

test('startConnection accepts enabled channel', async () => {
  const { service } = createService({
    booking: {
      id: 1,
      booking_number: 'TX202608130001',
      contact_status: CONTACT_STATUS.PENDING,
      status: BOOKING_STATUS.OPEN,
      is_urgent_request: 0,
      payment_method: 'PAY_DRIVER',
      payment_status: 'UNPAID',
      total_amount: 1000,
      currency: 'THB',
    },
    bookingById: {
      id: 1,
      booking_number: 'TX202608130001',
      contact_status: CONTACT_STATUS.PENDING,
      status: BOOKING_STATUS.OPEN,
      is_urgent_request: 0,
      payment_method: 'PAY_DRIVER',
      payment_status: 'UNPAID',
      total_amount: 1000,
      currency: 'THB',
    },
    enabledChannels: [{ code: 'WHATSAPP', enabled: true }],
  });

  const result = await service.startConnection(
    'TX202608130001',
    'WHATSAPP',
    null,
    'guest-token',
  );
  assert.equal(result.connection?.channel ?? result.contactChannel, 'WHATSAPP');
});

test('adminVerify retries dispatch when verified but dispatch incomplete', async () => {
  const previous = process.env.CONTACT_CONNECTION_REQUIRED;
  process.env.CONTACT_CONNECTION_REQUIRED = 'true';
  delete require.cache[require.resolve('../src/config/env')];
  delete require.cache[require.resolve('../src/policies/bookingDispatchEligibility.policy')];

  const booking = {
    id: 9,
    booking_number: 'TX202608130002',
    contact_status: CONTACT_STATUS.VERIFIED,
    status: BOOKING_STATUS.OPEN,
    is_urgent_request: 0,
    payment_method: 'PAY_DRIVER',
    payment_status: 'UNPAID',
    total_amount: 1500,
    currency: 'THB',
    metadata: JSON.stringify({}),
  };

  const { service, getDispatchCalls } = createService({
    booking,
    bookingById: booking,
    refreshedBooking: booking,
    connection: {
      id: 3,
      channel: 'LINE',
      status: CONTACT_STATUS.VERIFIED,
    },
    needsContactDispatchRetry: () => true,
  });

  const result = await service.adminVerify('TX202608130002', 42);
  assert.equal(result.dispatchStarted, true);
  assert.equal(getDispatchCalls(), 1);

  process.env.CONTACT_CONNECTION_REQUIRED = previous;
  delete require.cache[require.resolve('../src/config/env')];
  delete require.cache[require.resolve('../src/policies/bookingDispatchEligibility.policy')];
});

test('adminVerify does not redispatch when dispatch already completed', async () => {
  const previous = process.env.CONTACT_CONNECTION_REQUIRED;
  process.env.CONTACT_CONNECTION_REQUIRED = 'true';
  delete require.cache[require.resolve('../src/config/env')];
  delete require.cache[require.resolve('../src/policies/bookingDispatchEligibility.policy')];

  const booking = {
    id: 9,
    booking_number: 'TX202608130002',
    contact_status: CONTACT_STATUS.VERIFIED,
    status: BOOKING_STATUS.OPEN,
    is_urgent_request: 0,
    metadata: JSON.stringify({ contactDispatchCompleted: true }),
  };

  const { service, getDispatchCalls } = createService({
    booking,
    bookingById: booking,
    refreshedBooking: booking,
    connection: { id: 3, channel: 'LINE', status: CONTACT_STATUS.VERIFIED },
    needsContactDispatchRetry: () => false,
  });

  const result = await service.adminVerify('TX202608130002', 42);
  assert.equal(result.dispatchStarted, false);
  assert.equal(getDispatchCalls(), 0);

  process.env.CONTACT_CONNECTION_REQUIRED = previous;
  delete require.cache[require.resolve('../src/config/env')];
  delete require.cache[require.resolve('../src/policies/bookingDispatchEligibility.policy')];
});

test('mapPublicConnection includes urgent continuation fields without PII', async () => {
  const { service } = createService({});
  const mapped = service.mapPublicConnection(
    {
      booking_number: 'TX202608130003',
      contact_status: CONTACT_STATUS.CONFIRM_REQUESTED,
      contact_channel: 'LINE',
      contact_requested_at: '2026-08-13 10:00:00',
      contact_verified_at: null,
      is_urgent_request: 1,
      status: BOOKING_STATUS.OPEN,
      payment_method: 'PAY_DRIVER',
      payment_status: 'UNPAID',
      total_amount: 2000,
      currency: 'THB',
    },
    { id: 1, channel: 'LINE', status: CONTACT_STATUS.CONFIRM_REQUESTED },
  );

  assert.equal(mapped.isUrgentRequest, true);
  assert.equal(mapped.bookingStatus, BOOKING_STATUS.OPEN);
  assert.equal(mapped.totalAmount, 2000);
  assert.equal(mapped.paymentMethod, 'PAY_DRIVER');
  assert.equal(mapped.customerName, undefined);
  assert.equal(mapped.customerPhone, undefined);
});

test('confirmSent duplicate call on CONFIRM_REQUESTED is safe early return', async () => {
  let snapshotUpdates = 0;
  let connectionUpdates = 0;
  const booking = {
    id: 1,
    booking_number: 'TX202608130001',
    contact_status: CONTACT_STATUS.CONFIRM_REQUESTED,
    status: BOOKING_STATUS.OPEN,
  };
  const { service } = createService({
    booking,
    bookingById: booking,
    connection: {
      id: 2,
      channel: 'LINE',
      status: CONTACT_STATUS.CONFIRM_REQUESTED,
      customerConfirmedAt: '2026-08-13 10:00:00',
    },
  });
  service.contactConnectionRepository.updateConnectionStatus = async () => {
    connectionUpdates += 1;
  };
  service.contactConnectionRepository.updateBookingContactSnapshot = async () => {
    snapshotUpdates += 1;
  };

  const result = await service.confirmSent('TX202608130001', null, 'guest-token');
  assert.equal(result.contactStatus, CONTACT_STATUS.CONFIRM_REQUESTED);
  assert.equal(snapshotUpdates, 0);
  assert.equal(connectionUpdates, 0);
});

test('confirmSent on VERIFIED booking is safe no-op', async () => {
  let snapshotUpdates = 0;
  const booking = {
    id: 1,
    booking_number: 'TX202608130001',
    contact_status: CONTACT_STATUS.VERIFIED,
    status: BOOKING_STATUS.OPEN,
  };
  const { service } = createService({
    booking,
    bookingById: booking,
    connection: {
      id: 2,
      channel: 'LINE',
      status: CONTACT_STATUS.VERIFIED,
    },
  });
  service.contactConnectionRepository.updateBookingContactSnapshot = async () => {
    snapshotUpdates += 1;
  };

  const result = await service.confirmSent('TX202608130001', null, 'guest-token');
  assert.equal(result.contactStatus, CONTACT_STATUS.VERIFIED);
  assert.equal(snapshotUpdates, 0);
});
