const { test } = require('node:test');
const assert = require('node:assert/strict');

process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const BookingService = require('../src/services/booking.service');
const AppError = require('../src/utils/AppError');
const ERROR_CODES = require('../src/constants/errorCodes');

const BOOKING_NUMBER = 'TX202607010001';
const GUEST_TOKEN = 'guest-access-token-value';
const USER_ID = 42;
const OTHER_USER_ID = 99;

function createBooking(overrides = {}) {
  return {
    id: 10,
    booking_number: BOOKING_NUMBER,
    status: 'OPEN',
    customer_user_id: null,
    ...overrides,
  };
}

function createHarness({
  booking = createBooking(),
  guestTokenRecord = { id: 1 },
  claimAffectedRows = 1,
} = {}) {
  const calls = {
    beginTransaction: 0,
    commit: 0,
    rollback: 0,
    release: 0,
    findByBookingNumberForUpdate: 0,
    findActiveGuestTokenForBooking: 0,
    claimBookingOwnership: 0,
  };

  let bookingState = { ...booking };

  const conn = {
    async beginTransaction() {
      calls.beginTransaction += 1;
    },
    async commit() {
      calls.commit += 1;
    },
    async rollback() {
      calls.rollback += 1;
    },
    async release() {
      calls.release += 1;
    },
  };

  const bookingRepository = {
    async findByBookingNumberForUpdate(_conn, bookingNumber) {
      calls.findByBookingNumberForUpdate += 1;
      assert.equal(bookingNumber, BOOKING_NUMBER);
      return bookingState;
    },
    async findActiveGuestTokenForBooking(_conn, bookingId, _tokenHash) {
      calls.findActiveGuestTokenForBooking += 1;
      assert.equal(bookingId, bookingState?.id ?? booking.id);
      return guestTokenRecord;
    },
    async claimBookingOwnership(_conn, bookingId, userId) {
      calls.claimBookingOwnership += 1;
      assert.equal(bookingId, bookingState.id);
      assert.equal(userId, USER_ID);
      if (claimAffectedRows > 0) {
        bookingState = {
          ...bookingState,
          customer_user_id: userId,
        };
      }
      return claimAffectedRows;
    },
  };

  const pool = {
    async getConnection() {
      return conn;
    },
  };

  const service = new BookingService(
    pool,
    bookingRepository,
    {},
    {},
    {},
    {},
    {},
    {},
  );

  return { service, calls, setBooking(next) { bookingState = next; } };
}

test('claimBookingWithGuestToken links unclaimed guest booking', async () => {
  const { service, calls } = createHarness();

  const result = await service.claimBookingWithGuestToken({
    userId: USER_ID,
    bookingNumber: BOOKING_NUMBER,
    guestAccessToken: GUEST_TOKEN,
  });

  assert.deepEqual(result, { bookingNumber: BOOKING_NUMBER });
  assert.equal(calls.findActiveGuestTokenForBooking, 1);
  assert.equal(calls.claimBookingOwnership, 1);
  assert.equal(calls.commit, 1);
  assert.equal(calls.rollback, 0);
});

test('claimBookingWithGuestToken rejects invalid guestAccessToken with 403', async () => {
  const { service } = createHarness({ guestTokenRecord: null });

  await assert.rejects(
    () => service.claimBookingWithGuestToken({
      userId: USER_ID,
      bookingNumber: BOOKING_NUMBER,
      guestAccessToken: 'wrong-token',
    }),
    (err) => {
      assert.ok(err instanceof AppError);
      assert.equal(err.statusCode, 403);
      assert.equal(err.errorCode, ERROR_CODES.BOOKING_NOT_ACCESSIBLE);
      return true;
    },
  );
});

test('claimBookingWithGuestToken rejects expired guestAccessToken with 403', async () => {
  const { service } = createHarness({ guestTokenRecord: null });

  await assert.rejects(
    () => service.claimBookingWithGuestToken({
      userId: USER_ID,
      bookingNumber: BOOKING_NUMBER,
      guestAccessToken: GUEST_TOKEN,
    }),
    (err) => {
      assert.ok(err instanceof AppError);
      assert.equal(err.statusCode, 403);
      assert.equal(err.errorCode, ERROR_CODES.BOOKING_NOT_ACCESSIBLE);
      return true;
    },
  );
});

test('claimBookingWithGuestToken returns 404 for missing booking', async () => {
  const { service, setBooking } = createHarness();
  setBooking(null);

  await assert.rejects(
    () => service.claimBookingWithGuestToken({
      userId: USER_ID,
      bookingNumber: BOOKING_NUMBER,
      guestAccessToken: GUEST_TOKEN,
    }),
    (err) => {
      assert.ok(err instanceof AppError);
      assert.equal(err.statusCode, 404);
      assert.equal(err.errorCode, ERROR_CODES.BOOKING_NOT_FOUND);
      return true;
    },
  );
});

test('claimBookingWithGuestToken returns 409 when booking belongs to another user', async () => {
  const { service, setBooking } = createHarness();
  setBooking(createBooking({ customer_user_id: OTHER_USER_ID }));

  await assert.rejects(
    () => service.claimBookingWithGuestToken({
      userId: USER_ID,
      bookingNumber: BOOKING_NUMBER,
      guestAccessToken: GUEST_TOKEN,
    }),
    (err) => {
      assert.ok(err instanceof AppError);
      assert.equal(err.statusCode, 409);
      assert.equal(err.errorCode, ERROR_CODES.BOOKING_ALREADY_CLAIMED);
      return true;
    },
  );
});

test('claimBookingWithGuestToken is idempotent for same user', async () => {
  const { service, calls, setBooking } = createHarness();
  setBooking(createBooking({ customer_user_id: USER_ID }));

  const result = await service.claimBookingWithGuestToken({
    userId: USER_ID,
    bookingNumber: BOOKING_NUMBER,
    guestAccessToken: GUEST_TOKEN,
  });

  assert.deepEqual(result, { bookingNumber: BOOKING_NUMBER });
  assert.equal(calls.findActiveGuestTokenForBooking, 0);
  assert.equal(calls.claimBookingOwnership, 0);
  assert.equal(calls.commit, 1);
});

test('claimBookingWithGuestToken rejects empty guestAccessToken with 403', async () => {
  const { service } = createHarness();

  await assert.rejects(
    () => service.claimBookingWithGuestToken({
      userId: USER_ID,
      bookingNumber: BOOKING_NUMBER,
      guestAccessToken: '   ',
    }),
    (err) => {
      assert.ok(err instanceof AppError);
      assert.equal(err.statusCode, 403);
      assert.equal(err.errorCode, ERROR_CODES.BOOKING_NOT_ACCESSIBLE);
      return true;
    },
  );
});

test('claimBookingWithGuestToken handles claim race by returning idempotent success', async () => {
  const { service, calls } = createHarness({ claimAffectedRows: 0 });
  const originalFind = service.bookingRepository.findByBookingNumberForUpdate;
  let lookupCount = 0;
  service.bookingRepository.findByBookingNumberForUpdate = async (...args) => {
    lookupCount += 1;
    if (lookupCount === 1) {
      return createBooking();
    }
    return createBooking({ customer_user_id: USER_ID });
  };

  const result = await service.claimBookingWithGuestToken({
    userId: USER_ID,
    bookingNumber: BOOKING_NUMBER,
    guestAccessToken: GUEST_TOKEN,
  });

  assert.deepEqual(result, { bookingNumber: BOOKING_NUMBER });
  assert.equal(calls.claimBookingOwnership, 1);
  assert.equal(calls.commit, 1);
  service.bookingRepository.findByBookingNumberForUpdate = originalFind;
});
