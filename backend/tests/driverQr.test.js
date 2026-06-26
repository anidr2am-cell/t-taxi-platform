const { test } = require('node:test');
const assert = require('node:assert/strict');
const jwt = require('jsonwebtoken');
const request = require('supertest');

process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const DriverQrService = require('../src/services/driverQr.service');
const DriverJobService = require('../src/services/driverJob.service');
const BookingStatusService = require('../src/services/bookingStatus.service');
const ERROR_CODES = require('../src/constants/errorCodes');
const BOOKING_STATUS = require('../src/constants/reservationStatus');
const { hashToken } = require('../src/utils/tokenHash.util');
const container = require('../src/helpers/container');
const app = require('../src/app');

function sign(role = 'DRIVER', id = 44) {
  return jwt.sign(
    { sub: id, email: `${role.toLowerCase()}@example.com`, role, type: 'access' },
    process.env.JWT_ACCESS_SECRET,
    { expiresIn: '1h' },
  );
}

function row(overrides = {}) {
  return {
    id: 7,
    booking_number: 'TX202607010001',
    status: BOOKING_STATUS.DRIVER_ARRIVED,
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
    boarding_qr_used_at: null,
    dropoff_qr_token_hash: null,
    dropoff_qr_expires_at: null,
    dropoff_qr_used_at: null,
    ...overrides,
  };
}

function buildHarness(options = {}) {
  const calls = {
    begin: 0,
    commit: 0,
    rollback: 0,
    release: 0,
    boardingUsed: 0,
    dropoffUsed: 0,
    transitions: [],
    emitted: 0,
  };
  const conn = {
    async beginTransaction() { calls.begin += 1; },
    async commit() {
      calls.commit += 1;
      if (options.commitFails) throw new Error('commit failed');
    },
    async rollback() { calls.rollback += 1; },
    release() { calls.release += 1; },
  };
  const lockedRow = options.lockedRow === undefined ? row(options.row) : options.lockedRow;
  const detailRow = options.detailRow || lockedRow || row(options.row);
  const repo = {
    async findActiveDriverBookingByNumberForUpdate() {
      return lockedRow;
    },
    async findActiveDriverBookingByNumber() {
      return detailRow;
    },
    async findQrTokenBooking() {
      return options.tokenOwner || null;
    },
    async markBoardingQrUsed() {
      calls.boardingUsed += 1;
      return options.boardingConsumeResult ?? true;
    },
    async markDropoffQrUsed() {
      calls.dropoffUsed += 1;
      return options.dropoffConsumeResult ?? true;
    },
  };
  const realStatusService = new BookingStatusService(null, null);
  const statusService = {
    validateTransition: realStatusService.validateTransition.bind(realStatusService),
    async transitionInTransaction(_conn, bookingNumber, input, actor) {
      calls.transitions.push({ bookingNumber, input, actor });
      if (options.transitionFails) throw options.transitionFails;
      if (lockedRow?.status === input.status) {
        return {
          result: {
            bookingNumber,
            status: input.status,
            idempotent: true,
          },
          domainEvent: null,
          eventPayload: null,
        };
      }
      return {
        result: {
          bookingNumber,
          status: input.status,
          idempotent: false,
        },
        domainEvent: `event.${input.status}`,
        eventPayload: { bookingNumber, status: input.status },
      };
    },
    emitDomainEvent(domainEvent) {
      if (domainEvent) calls.emitted += 1;
    },
  };
  const service = new DriverQrService(
    { async getConnection() { return conn; } },
    repo,
    statusService,
    new DriverJobService(repo),
  );
  return { service, calls };
}

test('DRIVER_ASSIGNED -> DRIVER_ARRIVED uses BookingStatusService', async () => {
  const { service, calls } = buildHarness({
    row: { status: BOOKING_STATUS.DRIVER_ASSIGNED },
    detailRow: row({ status: BOOKING_STATUS.DRIVER_ARRIVED }),
  });

  const result = await service.markArrived(44, 'TX202607010001');

  assert.equal(result.status, BOOKING_STATUS.DRIVER_ARRIVED);
  assert.equal(calls.transitions[0].input.status, BOOKING_STATUS.DRIVER_ARRIVED);
  assert.equal(calls.emitted, 1);
});

test('repeated arrive request is idempotent', async () => {
  const { service, calls } = buildHarness({
    row: { status: BOOKING_STATUS.DRIVER_ARRIVED },
  });

  const result = await service.markArrived(44, 'TX202607010001');

  assert.equal(result.idempotent, true);
  assert.equal(calls.transitions.length, 1);
  assert.equal(calls.boardingUsed, 0);
  assert.equal(calls.emitted, 0);
});

test('wrong role is rejected before driver QR controller', async () => {
  container.register('driverQrService', () => ({
    async markArrived() {
      throw new Error('should not be called');
    },
  }));

  const res = await request(app)
    .post('/api/v1/driver/bookings/TX202607010001/arrive')
    .set('Authorization', `Bearer ${sign('CUSTOMER', 55)}`);

  assert.equal(res.status, 403);
  assert.equal(res.body.error_code, ERROR_CODES.FORBIDDEN);
});

test('other-driver booking is hidden', async () => {
  const { service } = buildHarness({ lockedRow: null });

  await assert.rejects(
    () => service.markArrived(44, 'TX202607010001'),
    (err) => err.errorCode === ERROR_CODES.BOOKING_NOT_FOUND,
  );
});

test('valid boarding scan consumes token, transitions, and makes dropoff QR eligible', async () => {
  const { service, calls } = buildHarness({
    detailRow: row({
      status: BOOKING_STATUS.PICKED_UP,
      dropoff_qr_token_hash: hashToken('dropoff-token'),
    }),
  });

  const result = await service.scanBoarding(44, 'TX202607010001', 'boarding-token');

  assert.equal(result.status, BOOKING_STATUS.PICKED_UP);
  assert.equal(result.dropoffQrEligible, true);
  assert.equal(calls.boardingUsed, 1);
  assert.equal(calls.transitions[0].input.status, BOOKING_STATUS.PICKED_UP);
  assert.equal(calls.emitted, 1);
});

test('boarding scan requires DRIVER_ARRIVED', async () => {
  const { service } = buildHarness({
    row: { status: BOOKING_STATUS.DRIVER_ASSIGNED },
  });

  await assert.rejects(
    () => service.scanBoarding(44, 'TX202607010001', 'boarding-token'),
    (err) => err.errorCode === ERROR_CODES.INVALID_STATUS_TRANSITION,
  );
});

test('expired boarding token is rejected', async () => {
  const { service } = buildHarness({
    row: { boarding_qr_expires_at: '2000-01-01 00:00:00' },
  });

  await assert.rejects(
    () => service.scanBoarding(44, 'TX202607010001', 'boarding-token'),
    (err) => err.errorCode === ERROR_CODES.QR_TOKEN_EXPIRED,
  );
});

test('wrong booking token is rejected', async () => {
  const { service } = buildHarness({
    row: { boarding_qr_token_hash: hashToken('other-token') },
    tokenOwner: { id: 99, booking_number: 'TX202607010099', token_type: 'BOARDING' },
  });

  await assert.rejects(
    () => service.scanBoarding(44, 'TX202607010001', 'boarding-token'),
    (err) => err.errorCode === ERROR_CODES.QR_TOKEN_BOOKING_MISMATCH,
  );
});

test('wrong QR type is rejected', async () => {
  const { service } = buildHarness({
    row: {
      boarding_qr_token_hash: hashToken('boarding-token'),
      dropoff_qr_token_hash: hashToken('dropoff-token'),
    },
  });

  await assert.rejects(
    () => service.scanBoarding(44, 'TX202607010001', 'dropoff-token'),
    (err) => err.errorCode === ERROR_CODES.QR_TOKEN_TYPE_MISMATCH,
  );
});

test('repeated boarding scan creates no duplicate side effects', async () => {
  const { service, calls } = buildHarness({
    row: {
      status: BOOKING_STATUS.PICKED_UP,
      boarding_qr_used_at: '2026-07-01 09:45:00',
      dropoff_qr_token_hash: hashToken('dropoff-token'),
      dropoff_qr_expires_at: '2099-01-01 00:00:00',
    },
    detailRow: row({ status: BOOKING_STATUS.PICKED_UP }),
  });

  const result = await service.scanBoarding(44, 'TX202607010001', 'boarding-token');

  assert.equal(result.idempotent, true);
  assert.equal(calls.boardingUsed, 0);
  assert.equal(calls.transitions.length, 0);
  assert.equal(calls.emitted, 0);
});

test('boarding scan does not generate driver-owned dropoff tokens', async () => {
  const { service, calls } = buildHarness({
    row: {
      dropoff_qr_token_hash: hashToken('dropoff-token'),
      dropoff_qr_expires_at: '2099-01-01 00:00:00',
    },
  });

  await service.scanBoarding(44, 'TX202607010001', 'boarding-token');

  assert.equal(calls.boardingUsed, 1);
});

test('valid dropoff scan completes the trip', async () => {
  const { service, calls } = buildHarness({
    row: {
      status: BOOKING_STATUS.PICKED_UP,
      dropoff_qr_token_hash: hashToken('dropoff-token'),
      dropoff_qr_expires_at: '2099-01-01 00:00:00',
    },
    detailRow: row({ status: BOOKING_STATUS.COMPLETED }),
  });

  const result = await service.scanDropoff(44, 'TX202607010001', 'dropoff-token');

  assert.equal(result.status, BOOKING_STATUS.COMPLETED);
  assert.equal(calls.dropoffUsed, 1);
  assert.equal(calls.transitions[0].input.status, BOOKING_STATUS.COMPLETED);
  assert.equal(calls.emitted, 1);
});

test('dropoff scan requires PICKED_UP', async () => {
  const { service } = buildHarness({
    row: {
      status: BOOKING_STATUS.DRIVER_ARRIVED,
      dropoff_qr_token_hash: hashToken('dropoff-token'),
      dropoff_qr_expires_at: '2099-01-01 00:00:00',
    },
  });

  await assert.rejects(
    () => service.scanDropoff(44, 'TX202607010001', 'dropoff-token'),
    (err) => err.errorCode === ERROR_CODES.INVALID_STATUS_TRANSITION,
  );
});

test('repeated dropoff scan creates no duplicate side effects', async () => {
  const { service, calls } = buildHarness({
    row: {
      status: BOOKING_STATUS.COMPLETED,
      dropoff_qr_token_hash: hashToken('dropoff-token'),
      dropoff_qr_expires_at: '2099-01-01 00:00:00',
      dropoff_qr_used_at: '2026-07-01 10:45:00',
    },
    detailRow: row({ status: BOOKING_STATUS.COMPLETED }),
  });

  const result = await service.scanDropoff(44, 'TX202607010001', 'dropoff-token');

  assert.equal(result.idempotent, true);
  assert.equal(calls.dropoffUsed, 0);
  assert.equal(calls.transitions.length, 0);
  assert.equal(calls.emitted, 0);
});

test('concurrent duplicate boarding scan protection rejects second consumption', async () => {
  const { service } = buildHarness({ boardingConsumeResult: false });

  await assert.rejects(
    () => service.scanBoarding(44, 'TX202607010001', 'boarding-token'),
    (err) => err.errorCode === ERROR_CODES.QR_TOKEN_ALREADY_USED,
  );
});

test('no event is emitted when transaction commit fails', async () => {
  const { service, calls } = buildHarness({ commitFails: true });

  await assert.rejects(
    () => service.scanBoarding(44, 'TX202607010001', 'boarding-token'),
    /commit failed/,
  );

  assert.equal(calls.emitted, 0);
  assert.equal(calls.rollback, 1);
});
