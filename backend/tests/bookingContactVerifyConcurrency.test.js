const test = require('node:test');
const assert = require('node:assert/strict');

process.env.NODE_ENV = 'test';
process.env.DB_USER = 'test';
process.env.DB_NAME = 'tride_test';
process.env.JWT_ACCESS_SECRET = 'test-access-secret';
process.env.JWT_REFRESH_SECRET = 'test-refresh-secret';
process.env.CONTACT_CONNECTION_REQUIRED = 'true';

delete require.cache[require.resolve('../src/config/env')];
delete require.cache[require.resolve('../src/policies/bookingDispatchEligibility.policy')];

const CONTACT_STATUS = require('../src/constants/contactStatus');
const BOOKING_STATUS = require('../src/constants/reservationStatus');
const BookingContactConnectionService = require('../src/services/bookingContactConnection.service');

test('concurrent admin verify dispatches only once', async () => {
  let verifyTransitions = 0;
  let dispatchCalls = 0;
  let locked = false;

  const bookingState = {
    id: 11,
    booking_number: 'TX202608130099',
    contact_status: CONTACT_STATUS.CONFIRM_REQUESTED,
    status: BOOKING_STATUS.OPEN,
    is_urgent_request: 0,
    payment_method: 'PAY_DRIVER',
    payment_status: 'UNPAID',
    total_amount: 1200,
    currency: 'THB',
    metadata: JSON.stringify({}),
  };

  const pool = {
    async getConnection() {
      return {
        async beginTransaction() {},
        async commit() {
          locked = false;
        },
        async rollback() {
          locked = false;
        },
        release() {},
      };
    },
  };

  const bookingRepository = {
    async findByBookingNumberForUpdate() {
      while (locked) {
        await new Promise((resolve) => setTimeout(resolve, 1));
      }
      locked = true;
      return { ...bookingState };
    },
    async findById() {
      return { ...bookingState };
    },
    async findContactBookingByNumber() {
      return { ...bookingState, contact_status: CONTACT_STATUS.VERIFIED };
    },
  };

  const contactConnectionRepository = {
    async findActiveByBookingId() {
      return {
        id: 4,
        channel: 'LINE',
        status: CONTACT_STATUS.CONFIRM_REQUESTED,
      };
    },
    async updateConnectionStatus(_conn, _id, patch) {
      if (bookingState.contact_status === CONTACT_STATUS.VERIFIED) return;
      verifyTransitions += 1;
      bookingState.contact_status = patch.status;
    },
    async updateBookingContactSnapshot(_conn, _id, patch) {
      bookingState.contact_status = patch.contactStatus;
    },
  };

  const bookingService = {
    formatDateTime: (date) => date.toISOString(),
    needsContactDispatchRetry: () => false,
    async dispatchAfterContactVerified() {
      dispatchCalls += 1;
      await new Promise((resolve) => setTimeout(resolve, 10));
      return true;
    },
  };

  const service = new BookingContactConnectionService(
    pool,
    bookingRepository,
    contactConnectionRepository,
    bookingService,
    { async getContactChannelsPublic() { return { channels: [] }; } },
  );

  const [first, second] = await Promise.all([
    service.adminVerify('TX202608130099', 1),
    service.adminVerify('TX202608130099', 2),
  ]);

  assert.equal(verifyTransitions, 1);
  assert.equal(dispatchCalls, 1);
  assert.equal(
    [first.dispatchStarted, second.dispatchStarted].filter(Boolean).length,
    1,
  );
});

test('admin verify retry after failed dispatch can redispatch once', async () => {
  let dispatchCalls = 0;
  let dispatchCompleted = false;
  const booking = {
    id: 12,
    booking_number: 'TX202608130088',
    contact_status: CONTACT_STATUS.VERIFIED,
    status: BOOKING_STATUS.OPEN,
    is_urgent_request: 0,
    metadata: JSON.stringify({}),
  };

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
    async findByBookingNumberForUpdate() {
      return { ...booking };
    },
    async findById() {
      return { ...booking };
    },
    async findContactBookingByNumber() {
      return { ...booking };
    },
  };

  const bookingService = {
    formatDateTime: (date) => date.toISOString(),
    needsContactDispatchRetry: () => !dispatchCompleted,
    async dispatchAfterContactVerified() {
      dispatchCalls += 1;
      if (dispatchCalls === 1) {
        throw new Error('dispatch failed');
      }
      dispatchCompleted = true;
      return true;
    },
  };

  const service = new BookingContactConnectionService(
    pool,
    bookingRepository,
    {
      async findActiveByBookingId() {
        return { id: 1, channel: 'LINE', status: CONTACT_STATUS.VERIFIED };
      },
    },
    bookingService,
    { async getContactChannelsPublic() { return { channels: [] }; } },
  );

  const first = await service.adminVerify('TX202608130088', 1);
  const second = await service.adminVerify('TX202608130088', 1);

  assert.equal(first.dispatchStarted, false);
  assert.equal(second.dispatchStarted, true);
  assert.equal(dispatchCalls, 2);
});
