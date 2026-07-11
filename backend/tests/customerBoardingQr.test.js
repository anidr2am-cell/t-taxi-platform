process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const test = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const app = require('../src/app');
const container = require('../src/helpers/container');
const BookingService = require('../src/services/booking.service');
const BOOKING_STATUS = require('../src/constants/reservationStatus');
const ERROR_CODES = require('../src/constants/errorCodes');
const { hashToken } = require('../src/utils/tokenHash.util');

function buildHarness(overrides = {}) {
  const calls = { hashes: [], commits: 0, rollbacks: 0 };
  let booking = {
    id: 7,
    booking_number: 'TX202607010001',
    customer_user_id: null,
    status: BOOKING_STATUS.DRIVER_ARRIVED,
    boarding_qr_token_hash: hashToken('old-token'),
    boarding_qr_expires_at: '2099-01-01 00:00:00',
    boarding_qr_used_at: null,
    ...overrides,
  };
  const conn = {
    async beginTransaction() {},
    async commit() { calls.commits += 1; },
    async rollback() { calls.rollbacks += 1; },
    release() {},
  };
  const repository = {
    async findByBookingNumberForUpdate() { return booking; },
    async findActiveGuestTokenForBooking(_conn, bookingId, tokenHash) {
      return bookingId === booking.id && tokenHash === hashToken('guest-token')
        ? { id: 1 }
        : null;
    },
    async setBoardingQr(_conn, bookingId, tokenHash, expiresAt) {
      calls.hashes.push({ bookingId, tokenHash, expiresAt });
      booking = {
        ...booking,
        boarding_qr_token_hash: tokenHash,
        boarding_qr_expires_at: expiresAt,
        boarding_qr_used_at: null,
      };
    },
  };
  const service = new BookingService(
    { async getConnection() { return conn; } },
    repository,
    null,
    null,
    null,
    null,
    null,
  );
  return { service, calls, getBooking: () => booking };
}

test('customer boarding QR issue requires booking-scoped guest access', async () => {
  const { service } = buildHarness();

  await assert.rejects(
    () => service.issueBoardingQr('TX202607010001', { guestAccessToken: 'wrong' }),
    (err) => err.errorCode === ERROR_CODES.BOOKING_NOT_ACCESSIBLE,
  );
});

test('customer boarding QR issue stores only hash and rejects duplicate active issue', async () => {
  const { service, calls, getBooking } = buildHarness({
    boarding_qr_token_hash: null,
    boarding_qr_expires_at: null,
  });

  const first = await service.issueBoardingQr(
    'TX202607010001',
    { guestAccessToken: 'guest-token' },
  );

  await assert.rejects(
    () => service.issueBoardingQr(
      'TX202607010001',
      { guestAccessToken: 'guest-token' },
    ),
    (err) => err.errorCode === ERROR_CODES.INVALID_STATUS_TRANSITION,
  );

  const second = await service.issueBoardingQr(
    'TX202607010001',
    { guestAccessToken: 'guest-token', forceReissue: true },
  );

  assert.notEqual(first.boardingQrToken, second.boardingQrToken);
  assert.equal(calls.hashes.length, 2);
  assert.equal(
    getBooking().boarding_qr_token_hash,
    hashToken(second.boardingQrToken),
  );
  assert.notEqual(calls.hashes[1].tokenHash, second.boardingQrToken);
  assert.equal(calls.commits, 2);
});

test('customer boarding QR cannot be issued after pickup or consumption', async () => {
  const { service } = buildHarness({
    status: BOOKING_STATUS.PICKED_UP,
    boarding_qr_used_at: '2026-07-01 09:45:00',
  });

  await assert.rejects(
    () => service.issueBoardingQr(
      'TX202607010001',
      { guestAccessToken: 'guest-token' },
    ),
    (err) => err.errorCode === ERROR_CODES.INVALID_STATUS_TRANSITION,
  );
});

test('customer boarding QR route returns production-safe issue response', async () => {
  container.register('bookingService', () => ({
    async issueBoardingQr(bookingNumber, input) {
      assert.equal(bookingNumber, 'TX202607010001');
      assert.equal(input.guestAccessToken, 'guest-token');
      return {
        bookingNumber,
        status: BOOKING_STATUS.DRIVER_ARRIVED,
        boardingQrToken: 'new-boarding-token',
        boardingQrExpiresAt: '2099-01-01 00:00:00',
      };
    },
  }));

  const response = await request(app)
    .post('/api/v1/bookings/TX202607010001/boarding-qr/issue')
    .send({ guestAccessToken: 'guest-token' });

  assert.equal(response.statusCode, 200);
  assert.equal(response.body.data.boardingQrToken, 'new-boarding-token');
});
