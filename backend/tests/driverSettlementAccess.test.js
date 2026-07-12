process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const { test } = require('node:test');
const assert = require('node:assert/strict');

const BookingRepository = require('../src/repositories/booking.repository');
const COMMISSION_STATUS = require('../src/constants/commissionStatus');
const CommissionSettlementService = require('../src/services/commissionSettlement.service');
const ERROR_CODES = require('../src/constants/errorCodes');
const ROLES = require('../src/constants/roles');

function createCapturePool() {
  const calls = [];
  return {
    calls,
    query: async (sql, params) => {
      calls.push({ sql, params });
      if (sql.includes('SELECT 1')) return [[{ ok: 1 }]];
      if (sql.includes('COUNT(*)')) return [[{ total: 0 }]];
      return [[]];
    },
  };
}

test('driverOwnsSettlementBooking accepts SETTLEMENT_PENDING bookings', async () => {
  const pool = createCapturePool();
  const repo = new BookingRepository(pool);
  const owns = await repo.driverOwnsSettlementBooking(5, 'TX202607120002');
  assert.equal(owns, true);
  assert.match(pool.calls[0].sql, /SETTLEMENT_PENDING/);
  assert.match(pool.calls[0].sql, /COMPLETED/);
  assert.doesNotMatch(pool.calls[0].sql, /status = 'COMPLETED'/);
});

test('findDriverSettlements includes SETTLEMENT_PENDING commission rows', async () => {
  const pool = createCapturePool();
  const repo = new BookingRepository(pool);
  await repo.findDriverSettlements(5);
  assert.match(pool.calls[0].sql, /SETTLEMENT_PENDING/);
  assert.match(pool.calls[0].sql, /COALESCE\(b\.completed_at, b\.updated_at\)/);
});

test('admin settlement filters include SETTLEMENT_PENDING bookings', async () => {
  const pool = createCapturePool();
  const repo = new BookingRepository(pool);
  await repo.findAdminSettlements({}, { limit: 20, offset: 0 });
  assert.match(pool.calls[0].sql, /SETTLEMENT_PENDING/);
});

test('getDriverSettlement succeeds for SETTLEMENT_PENDING + DUE without separate settlement row', async () => {
  const bookingRepo = {
    async driverOwnsSettlementBooking(driverId, bookingNumber) {
      return driverId === 5 && bookingNumber === 'TX202607120002';
    },
    async findSettlementByBookingNumber(bookingNumber) {
      if (bookingNumber !== 'TX202607120002') return null;
      return {
        booking_number: bookingNumber,
        status: 'SETTLEMENT_PENDING',
        pickup_date: '2026-07-12',
        pickup_time: '09:00',
        origin_address: 'BKK',
        destination_address: 'Hotel',
        completed_at: null,
        commission_status: COMMISSION_STATUS.DUE,
        commission_amount: 200,
        commission_due_at: null,
        commission_paid_at: null,
        commission_receipt_file_id: null,
        metadata: null,
        currency: 'THB',
        driver_id: 5,
      };
    },
  };
  const driverRepo = {
    async findByUserId() { return { id: 5 }; },
  };
  const service = new CommissionSettlementService({}, bookingRepo, driverRepo, {}, {});
  service.reconcileMissingObligationForBooking = async () => {};

  const item = await service.getDriverSettlement(
    44,
    'TX202607120002',
    '/api/v1/driver/settlements',
  );

  assert.equal(item.bookingNumber, 'TX202607120002');
  assert.equal(item.status, 'SETTLEMENT_PENDING');
  assert.equal(item.commissionAmount, 200);
  assert.equal(item.commissionStatus, 'PENDING');
});

test('getDriverSettlement rejects another driver booking', async () => {
  const bookingRepo = {
    async driverOwnsSettlementBooking() { return false; },
    async findSettlementByBookingNumber() {
      return {
        booking_number: 'TX202607120002',
        status: 'SETTLEMENT_PENDING',
        commission_status: COMMISSION_STATUS.DUE,
        commission_amount: 200,
        currency: 'THB',
      };
    },
  };
  const driverRepo = {
    async findByUserId() { return { id: 5 }; },
  };
  const service = new CommissionSettlementService({}, bookingRepo, driverRepo, {}, {});

  await assert.rejects(
    () => service.getDriverSettlement(44, 'TX202607120002', '/api/v1/driver/settlements'),
    (err) => err.errorCode === ERROR_CODES.SETTLEMENT_NOT_FOUND,
  );
});

test('getAdminSettlement exposes SETTLEMENT_PENDING booking for admin review', async () => {
  const bookingRepo = {
    async findSettlementByBookingNumber() {
      return {
        booking_number: 'TX202607120002',
        status: 'SETTLEMENT_PENDING',
        completed_at: null,
        total_amount: 1600,
        currency: 'THB',
        commission_status: COMMISSION_STATUS.DUE,
        commission_amount: 200,
        commission_due_at: null,
        commission_paid_at: null,
        commission_receipt_file_id: null,
        metadata: null,
        driver_id: 5,
        driver_name: 'Driver A',
        driver_phone: '+6600',
      };
    },
  };
  const service = new CommissionSettlementService({}, bookingRepo, {}, {}, {});
  service.reconcileMissingObligationForBooking = async () => {};

  const detail = await service.getAdminSettlement('TX202607120002', '/api/v1/admin/settlements');
  assert.equal(detail.status, 'SETTLEMENT_PENDING');
  assert.equal(detail.commissionAmount, 200);
  assert.equal(detail.commissionStatus, 'PENDING');
});
