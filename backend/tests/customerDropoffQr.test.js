const { test } = require('node:test');
const assert = require('node:assert/strict');

process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const BookingService = require('../src/services/booking.service');
const DriverQrService = require('../src/services/driverQr.service');
const DriverJobService = require('../src/services/driverJob.service');
const BookingStatusService = require('../src/services/bookingStatus.service');
const ERROR_CODES = require('../src/constants/errorCodes');
const BOOKING_STATUS = require('../src/constants/reservationStatus');
const ROLES = require('../src/constants/roles');
const { hashToken } = require('../src/utils/tokenHash.util');

function booking(overrides = {}) {
  return {
    id: 7,
    booking_number: 'TX202607010001',
    status: BOOKING_STATUS.PICKED_UP,
    customer_user_id: 88,
    dropoff_qr_token_hash: null,
    dropoff_qr_expires_at: null,
    dropoff_qr_used_at: null,
    ...overrides,
  };
}

function driverRow(overrides = {}) {
  return {
    id: 7,
    booking_number: 'TX202607010001',
    status: BOOKING_STATUS.PICKED_UP,
    pickup_date: '2026-07-01',
    pickup_time: '09:30',
    origin_address: 'BKK Airport',
    destination_address: 'Pattaya Hotel',
    customer_name: 'Kim',
    customer_phone: '+66123456789',
    special_requests: null,
    payment_method: 'PAY_DRIVER',
    service_type_code: 'AIRPORT_PICKUP',
    service_type_name: 'Airport Pickup',
    vehicle_type_code: 'SUV',
    vehicle_type_name: 'SUV',
    adults: 2,
    children: 0,
    infants: 0,
    carriers_20_inch: 1,
    carriers_24_inch_plus: 1,
    golf_bags: 0,
    special_items: null,
    flight_number: null,
    flight_estimated_arrival_at_text: null,
    delay_status: null,
    delay_minutes: null,
    boarding_qr_token_hash: hashToken('boarding-token'),
    boarding_qr_expires_at: '2099-01-01 00:00:00',
    boarding_qr_used_at: '2026-07-01 09:45:00',
    dropoff_qr_token_hash: hashToken('new-token'),
    dropoff_qr_expires_at: '2099-01-01 00:00:00',
    dropoff_qr_used_at: null,
    ...overrides,
  };
}

function buildIssueHarness(options = {}) {
  const calls = {
    begin: 0,
    commit: 0,
    rollback: 0,
    release: 0,
    setDropoffQr: [],
    guestLookups: [],
    statusLogs: 0,
    activityLogs: 0,
  };
  let currentBooking = booking(options.booking);
  const conn = {
    async beginTransaction() { calls.begin += 1; },
    async commit() { calls.commit += 1; },
    async rollback() { calls.rollback += 1; },
    release() { calls.release += 1; },
  };
  const repo = {
    async findByBookingNumberForUpdate(_conn, bookingNumber) {
      if (options.bookingNumberMismatch && bookingNumber !== 'TX202607010002') {
        return booking({ id: 99, booking_number: bookingNumber });
      }
      return options.notFound ? null : currentBooking;
    },
    async findActiveGuestTokenForBooking(_conn, bookingId, tokenHash) {
      calls.guestLookups.push({ bookingId, tokenHash });
      if (options.guestTokenValid === false) return null;
      if (bookingId !== currentBooking.id) return null;
      return tokenHash === hashToken('guest-token') ? { id: 1 } : null;
    },
    async setDropoffQr(_conn, bookingId, tokenHash, expiresAt) {
      calls.setDropoffQr.push({ bookingId, tokenHash, expiresAt });
      currentBooking = {
        ...currentBooking,
        dropoff_qr_token_hash: tokenHash,
        dropoff_qr_expires_at: expiresAt,
        dropoff_qr_used_at: null,
      };
    },
    async insertStatusLog() { calls.statusLogs += 1; },
    async insertActivityLog() { calls.activityLogs += 1; },
  };
  const service = new BookingService(
    { async getConnection() { return conn; } },
    repo,
    null,
    null,
    null,
    null,
    null,
  );
  return { service, calls, getBooking: () => currentBooking };
}

test('unauthorized dropoff QR issue request is rejected', async () => {
  const { service } = buildIssueHarness();

  await assert.rejects(
    () => service.issueDropoffQr('TX202607010001', {}),
    (err) => err.errorCode === ERROR_CODES.BOOKING_NOT_ACCESSIBLE,
  );
});

test('wrong guest token is rejected', async () => {
  const { service } = buildIssueHarness();

  await assert.rejects(
    () => service.issueDropoffQr('TX202607010001', { guestAccessToken: 'wrong' }),
    (err) => err.errorCode === ERROR_CODES.BOOKING_NOT_ACCESSIBLE,
  );
});

test('booking-number mismatch is rejected because guest token is scoped to the booking', async () => {
  const { service } = buildIssueHarness({ bookingNumberMismatch: true });

  await assert.rejects(
    () => service.issueDropoffQr('TX202607010099', { guestAccessToken: 'guest-token' }),
    (err) => err.errorCode === ERROR_CODES.BOOKING_NOT_ACCESSIBLE,
  );
});

test('status before PICKED_UP is rejected', async () => {
  const { service } = buildIssueHarness({
    booking: { status: BOOKING_STATUS.DRIVER_ARRIVED },
  });

  await assert.rejects(
    () => service.issueDropoffQr('TX202607010001', { guestAccessToken: 'guest-token' }),
    (err) => err.errorCode === ERROR_CODES.INVALID_STATUS_TRANSITION,
  );
});

test('valid customer issue returns raw token', async () => {
  const { service } = buildIssueHarness();

  const result = await service.issueDropoffQr(
    'TX202607010001',
    {},
    { id: 88, role: ROLES.CUSTOMER },
  );

  assert.equal(result.bookingNumber, 'TX202607010001');
  assert.equal(result.status, BOOKING_STATUS.PICKED_UP);
  assert.equal(typeof result.dropoffQrToken, 'string');
  assert.ok(result.dropoffQrToken.length > 20);
});

test('database stores hash, not raw token, and writes no lifecycle logs', async () => {
  const { service, calls } = buildIssueHarness();

  const result = await service.issueDropoffQr(
    'TX202607010001',
    { guestAccessToken: 'guest-token' },
  );

  assert.equal(calls.setDropoffQr.length, 1);
  assert.notEqual(calls.setDropoffQr[0].tokenHash, result.dropoffQrToken);
  assert.equal(calls.setDropoffQr[0].tokenHash, hashToken(result.dropoffQrToken));
  assert.equal(calls.statusLogs, 0);
  assert.equal(calls.activityLogs, 0);
});

test('repeated issue rotates token and invalidates previous unused token', async () => {
  const { service, calls, getBooking } = buildIssueHarness();

  const first = await service.issueDropoffQr(
    'TX202607010001',
    { guestAccessToken: 'guest-token' },
  );
  const second = await service.issueDropoffQr(
    'TX202607010001',
    { guestAccessToken: 'guest-token' },
  );

  assert.notEqual(first.dropoffQrToken, second.dropoffQrToken);
  assert.equal(calls.setDropoffQr.length, 2);
  assert.equal(getBooking().dropoff_qr_token_hash, hashToken(second.dropoffQrToken));
  assert.equal(getBooking().dropoff_qr_token_hash === hashToken(first.dropoffQrToken), false);
});

test('old rotated token is rejected by driver scan and newest token is accepted', async () => {
  const realStatusService = new BookingStatusService(null, null);
  const calls = { dropoffUsed: 0, transitions: 0, emitted: 0 };
  const conn = {
    async beginTransaction() {},
    async commit() {},
    async rollback() {},
    release() {},
  };
  const repo = {
    async findActiveDriverBookingByNumberForUpdate() {
      return driverRow();
    },
    async findActiveDriverBookingByNumber() {
      return driverRow({ status: BOOKING_STATUS.COMPLETED });
    },
    async findQrTokenBooking(_conn, tokenHash) {
      if (tokenHash === hashToken('old-token')) {
        return { id: 7, booking_number: 'TX202607010001', token_type: 'DROPOFF' };
      }
      return null;
    },
    async markDropoffQrUsed() {
      calls.dropoffUsed += 1;
      return true;
    },
  };
  const statusService = {
    validateTransition: realStatusService.validateTransition.bind(realStatusService),
    async transitionInTransaction() {
      calls.transitions += 1;
      return {
        result: { status: BOOKING_STATUS.COMPLETED },
        domainEvent: 'trip.completed',
        eventPayload: {},
        outboxId: null,
      };
    },
    emitDomainEvent() {
      calls.emitted += 1;
    },
    async dispatchOutboxAfterCommit() {},
  };
  const service = new DriverQrService(
    { async getConnection() { return conn; } },
    repo,
    statusService,
    new DriverJobService(repo),
  );

  await assert.rejects(
    () => service.scanDropoff(44, 'TX202607010001', 'old-token'),
    (err) => err.errorCode === ERROR_CODES.INVALID_QR_TOKEN,
  );

  const result = await service.scanDropoff(44, 'TX202607010001', 'new-token');
  assert.equal(result.status, BOOKING_STATUS.COMPLETED);
  assert.equal(calls.dropoffUsed, 1);
  assert.equal(calls.transitions, 1);
  assert.equal(calls.emitted, 1);
});

test('COMPLETED booking cannot issue another token', async () => {
  const { service } = buildIssueHarness({
    booking: { status: BOOKING_STATUS.COMPLETED },
  });

  await assert.rejects(
    () => service.issueDropoffQr('TX202607010001', { guestAccessToken: 'guest-token' }),
    (err) => err.errorCode === ERROR_CODES.INVALID_STATUS_TRANSITION,
  );
});

test('raw token is not returned in driver response where testable', async () => {
  const realStatusService = new BookingStatusService(null, null);
  const conn = {
    async beginTransaction() {},
    async commit() {},
    async rollback() {},
    release() {},
  };
  const repo = {
    async findActiveDriverBookingByNumberForUpdate() {
      return driverRow({ dropoff_qr_token_hash: hashToken('customer-token') });
    },
    async findActiveDriverBookingByNumber() {
      return driverRow({ status: BOOKING_STATUS.COMPLETED });
    },
    async findQrTokenBooking() { return null; },
    async markDropoffQrUsed() { return true; },
  };
  const service = new DriverQrService(
    { async getConnection() { return conn; } },
    repo,
    {
      validateTransition: realStatusService.validateTransition.bind(realStatusService),
      async transitionInTransaction() {
        return {
          result: { status: BOOKING_STATUS.COMPLETED },
          domainEvent: null,
          eventPayload: null,
        };
      },
      emitDomainEvent() {},
      async dispatchOutboxAfterCommit() {},
    },
    new DriverJobService(repo),
  );

  const result = await service.scanDropoff(44, 'TX202607010001', 'customer-token');
  assert.equal(JSON.stringify(result).includes('customer-token'), false);
});

test('concurrent-style repeated issuance leaves exactly one latest valid hash', async () => {
  const { service, calls, getBooking } = buildIssueHarness();

  const tokens = await Promise.all([
    service.issueDropoffQr('TX202607010001', { guestAccessToken: 'guest-token' }),
    service.issueDropoffQr('TX202607010001', { guestAccessToken: 'guest-token' }),
  ]);
  const latestHash = calls.setDropoffQr.at(-1).tokenHash;

  assert.equal(getBooking().dropoff_qr_token_hash, latestHash);
  assert.equal(
    tokens.filter((item) => hashToken(item.dropoffQrToken) === latestHash).length,
    1,
  );
});
