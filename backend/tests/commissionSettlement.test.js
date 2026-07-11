process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const fs = require('fs');
const path = require('path');
const { test } = require('node:test');
const assert = require('node:assert/strict');
const jwt = require('jsonwebtoken');
const request = require('supertest');
const { appEvents, EVENTS } = require('../src/events');
const { uploadDir } = require('../src/config/multer');

const ERROR_CODES = require('../src/constants/errorCodes');
const COMMISSION_STATUS = require('../src/constants/commissionStatus');
const ROLES = require('../src/constants/roles');
const CommissionSettlementService = require('../src/services/commissionSettlement.service');
const container = require('../src/helpers/container');
const app = require('../src/app');

function sign(role = 'DRIVER', id = 44) {
  return jwt.sign(
    { sub: id, email: `${role.toLowerCase()}@example.com`, role, type: 'access' },
    process.env.JWT_ACCESS_SECRET,
    { expiresIn: '1h' },
  );
}

function sqlDateFromNow(days) {
  return new Date(Date.now() + days * 86400000).toISOString().slice(0, 19).replace('T', ' ');
}

function settlementRow(overrides = {}) {
  return {
    id: 7,
    booking_number: 'TX202607010001',
    status: 'COMPLETED',
    completed_at: '2026-07-01 12:00:00',
    total_amount: 1200,
    currency: 'THB',
    commission_status: COMMISSION_STATUS.DUE,
    commission_amount: 120,
    commission_due_at: sqlDateFromNow(7),
    commission_paid_at: null,
    commission_receipt_file_id: null,
    metadata: null,
    driver_id: 5,
    driver_name: 'Driver A',
    driver_phone: '+6600',
    receipt_mime_type: null,
    receipt_file_size: null,
    receipt_original_filename: null,
    receipt_uploaded_at: null,
    ...overrides,
  };
}

test('commission obligation created once after COMPLETED event', async () => {
  let updateCalls = 0;
  const conn = {
    async beginTransaction() {},
    async commit() {},
    async rollback() {},
    release() {},
    async query(sql, params) {
      if (sql.includes('FOR UPDATE') && sql.includes('FROM bookings')) {
        return [[{
          id: 7,
          booking_number: 'TX202607010001',
          status: 'COMPLETED',
          total_amount: 1200,
          currency: 'THB',
          commission_status: COMMISSION_STATUS.NOT_DUE_YET,
          commission_amount: null,
          completed_at: '2026-07-01 12:00:00',
        }]];
      }
      return [[], []];
    },
  };
  const pool = { async getConnection() { return conn; } };
  const bookingRepo = {
    async updateCommissionFields() { updateCalls += 1; },
    async insertActivityLog() {},
  };
  const settingsRepo = {
    async findByGroupAndKey(_g, key) {
      if (key === 'commission_rate_percent') return { value: '10' };
      if (key === 'commission_due_days') return { value: '7' };
      return null;
    },
  };
  const service = new CommissionSettlementService(
    pool,
    bookingRepo,
    {},
    {},
    settingsRepo,
  );

  await service.activateObligationForCompletedBooking(7);
  assert.equal(updateCalls, 1);
});

test('duplicate completion event does not duplicate obligation', async () => {
  let updateCalls = 0;
  const conn = {
    async beginTransaction() {},
    async commit() {},
    async rollback() {},
    release() {},
    async query() {
      return [[{
        id: 7,
        booking_number: 'TX202607010001',
        status: 'COMPLETED',
        total_amount: 1200,
        currency: 'THB',
        commission_status: COMMISSION_STATUS.DUE,
        commission_amount: 120,
        completed_at: '2026-07-01 12:00:00',
      }]];
    },
  };
  const pool = { async getConnection() { return conn; } };
  const bookingRepo = {
    async updateCommissionFields() { updateCalls += 1; },
    async insertActivityLog() {},
  };
  const settingsRepo = {
    async findByGroupAndKey() { return { value: '10' }; },
  };
  const service = new CommissionSettlementService(
    pool,
    bookingRepo,
    {},
    {},
    settingsRepo,
  );

  await service.activateObligationForCompletedBooking(7);
  assert.equal(updateCalls, 0);
});

test('DRIVER can list settlements', async () => {
  container.register('commissionSettlementService', () => ({
    async listDriverSettlements() {
      return [{ bookingNumber: 'TX202607010001', commissionStatus: 'PENDING' }];
    },
  }));

  const res = await request(app)
    .get('/api/v1/driver/settlements')
    .set('Authorization', `Bearer ${sign('DRIVER', 44)}`);

  assert.equal(res.status, 200);
  assert.equal(res.body.data.items.length, 1);
});

test('CUSTOMER cannot access driver settlements', async () => {
  const res = await request(app)
    .get('/api/v1/driver/settlements')
    .set('Authorization', `Bearer ${sign('CUSTOMER', 8)}`);
  assert.equal(res.status, 403);
});

test('ADMIN can list settlements', async () => {
  container.register('commissionSettlementService', () => ({
    async listAdminSettlements() {
      return { page: 1, pageSize: 20, total: 0, items: [] };
    },
  }));

  const res = await request(app)
    .get('/api/v1/admin/settlements')
    .set('Authorization', `Bearer ${sign('SUPER_ADMIN', 1)}`);
  assert.equal(res.status, 200);
});

test('DRIVER cannot access admin settlements', async () => {
  const res = await request(app)
    .get('/api/v1/admin/settlements')
    .set('Authorization', `Bearer ${sign('DRIVER', 44)}`);
  assert.equal(res.status, 403);
});

test('upload rejects after APPROVED', async () => {
  const bookingRepo = {
    async findSettlementByBookingNumberForUpdate() {
      return settlementRow({ commission_status: COMMISSION_STATUS.PAID, commission_receipt_file_id: 9 });
    },
    async driverOwnsSettlementBooking() { return true; },
  };
  const driverRepo = {
    async findByUserId() { return { id: 5 }; },
  };
  const conn = {
    async beginTransaction() {},
    async commit() {},
    async rollback() {},
    release() {},
  };
  const pool = { async getConnection() { return conn; } };
  const service = new CommissionSettlementService(pool, bookingRepo, driverRepo, {}, {});

  const tmp = path.join(uploadDir, 'test-upload.bin');
  fs.writeFileSync(tmp, 'data');
  await assert.rejects(
    () => service.uploadReceipt(44, 'TX202607010001', {
      path: tmp,
      mimetype: 'application/pdf',
      size: 4,
      originalname: 'receipt.pdf',
    }),
    (err) => err.errorCode === ERROR_CODES.RECEIPT_ALREADY_APPROVED,
  );
  if (fs.existsSync(tmp)) fs.unlinkSync(tmp);
});

test('invalid MIME rejected', () => {
  const service = new CommissionSettlementService({}, {}, {}, {}, {});
  assert.throws(
    () => service.validateUploadedFile({ mimetype: 'text/plain', originalname: 'a.txt' }),
    (err) => err.errorCode === ERROR_CODES.INVALID_FILE_TYPE,
  );
});

test('path traversal filename neutralized', () => {
  const service = new CommissionSettlementService({}, {}, {}, {}, {});
  const name = service.safeStoredFilename({
    originalname: '../../evil.pdf',
    mimetype: 'application/pdf',
  });
  assert.ok(!name.includes('..'));
  assert.ok(name.endsWith('.pdf'));
});

test('successful approval is idempotent', async () => {
  let activityLogs = 0;
  const bookingRepo = {
    async findSettlementByBookingNumberForUpdate() {
      return settlementRow({
        status: 'COMPLETED',
        commission_receipt_file_id: 11,
        commission_status: COMMISSION_STATUS.PAID,
      });
    },
    async findSettlementByBookingNumber() {
      return settlementRow({
        status: 'COMPLETED',
        commission_receipt_file_id: 11,
        commission_status: COMMISSION_STATUS.PAID,
        commission_paid_at: '2026-07-02 10:00:00',
      });
    },
    async updateCommissionFields() {},
    async insertActivityLog() { activityLogs += 1; },
  };
  const conn = {
    async beginTransaction() {},
    async commit() {},
    async rollback() {},
    release() {},
  };
  const pool = { async getConnection() { return conn; } };
  const service = new CommissionSettlementService(pool, bookingRepo, {}, {}, {});
  const actor = { id: 1, role: ROLES.ADMIN };

  await service.approve('TX202607010001', actor);
  assert.equal(activityLogs, 0);
});

test('rejection requires reason via validator', async () => {
  const res = await request(app)
    .post('/api/v1/admin/settlements/TX202607010001/reject')
    .set('Authorization', `Bearer ${sign('ADMIN', 1)}`)
    .send({});
  assert.equal(res.status, 400);
});

test('overdue blocking prevents assignment', async () => {
  const bookingRepo = {};
  const driverRepo = {
    async findByIdForUpdate() {
      return { id: 5, name: 'Driver', phone: '+6600', is_active: 1, status: 'AVAILABLE' };
    },
    async hasActiveJob() { return false; },
  };
  const settlementService = {
    async driverHasBlockingSettlement() { return true; },
  };
  const AdminDispatchService = require('../src/services/adminDispatch.service');
  const conn = {
    async beginTransaction() {},
    async commit() {},
    async rollback() {},
    release() {},
  };
  const pool = { async getConnection() { return conn; } };
  const service = new AdminDispatchService(
    pool,
    bookingRepo,
    driverRepo,
    {},
    settlementService,
    null,
    null,
    new (require('../src/services/driverCandidateScoring.service'))(),
  );

  await assert.rejects(
    () => service.ensureDriverEligible(conn, 5),
    (err) => err.errorCode === ERROR_CODES.DRIVER_NOT_ELIGIBLE,
  );
});

test('unresolved settlement blocks even before its due date', async () => {
  const futureDue = new Date(Date.now() + 86400000).toISOString().slice(0, 19).replace('T', ' ');
  const bookingRepo = {
    async findUnpaidSettlementsForDriver() {
      return [{
        commission_status: COMMISSION_STATUS.DUE,
        commission_due_at: futureDue,
        commission_receipt_file_id: null,
        metadata: null,
      }];
    },
  };
  const service = new CommissionSettlementService({}, bookingRepo, {}, {}, {});
  const blocked = await service.driverHasBlockingSettlement(5);
  assert.equal(blocked, true);
});

test('overdue with receipt still blocks assignment', async () => {
  const pastDue = '2020-01-01 00:00:00';
  const bookingRepo = {
    async findUnpaidSettlementsForDriver() {
      return [{
        commission_status: COMMISSION_STATUS.DUE,
        commission_due_at: pastDue,
        commission_receipt_file_id: 42,
        metadata: { commissionReceiptSubmittedAt: '2020-01-02T00:00:00.000Z' },
      }];
    },
  };
  const service = new CommissionSettlementService({}, bookingRepo, {}, {}, {});
  const blocked = await service.driverHasBlockingSettlement(5);
  assert.equal(blocked, true);
});

test('reconciliation creates obligation for completed booking without event', async () => {
  let activateCalls = 0;
  const bookingRepo = {
    async findCompletedBookingIdsMissingObligation() { return [7, 8]; },
  };
  const service = new CommissionSettlementService({}, bookingRepo, {}, {}, {});
  service.activateObligationForCompletedBooking = async (id) => {
    activateCalls += 1;
    assert.ok([7, 8].includes(id));
  };
  await service.reconcileMissingObligationsForDriver(5);
  assert.equal(activateCalls, 2);
});

test('mapSettlementListItem includes trip summary fields with null-safe addresses', () => {
  const service = new CommissionSettlementService({}, {}, {}, {}, {});
  const item = service.mapSettlementListItem(
    settlementRow({
      pickup_date: '2026-07-01',
      pickup_time: '09:30:00',
      origin_address: 'BKK Airport',
      destination_address: 'Pattaya Hotel',
    }),
    '/api/v1/driver/settlements',
    ROLES.DRIVER,
  );
  assert.equal(item.pickupDate, '2026-07-01');
  assert.equal(item.pickupTime, '09:30:00');
  assert.equal(item.origin, 'BKK Airport');
  assert.equal(item.destination, 'Pattaya Hotel');
  assert.equal(item.driverId, undefined);
  assert.equal(item.driverName, undefined);

  const nullItem = service.mapSettlementListItem(
    settlementRow({
      origin_address: null,
      destination_address: null,
      pickup_date: null,
      pickup_time: null,
    }),
    '/api/v1/driver/settlements',
    ROLES.DRIVER,
  );
  assert.equal(nullItem.origin, null);
  assert.equal(nullItem.destination, null);
});

test('admin settlement list item keeps driver summary fields', () => {
  const service = new CommissionSettlementService({}, {}, {}, {}, {});
  const item = service.mapSettlementListItem(
    settlementRow(),
    '/api/v1/admin/settlements',
    ROLES.ADMIN,
  );
  assert.equal(item.driverId, 5);
  assert.equal(item.driverName, 'Driver A');
});

test('getDriverSettlement reconciles missing obligation on access', async () => {
  let activated = false;
  const driverRepo = {
    async findByUserId() { return { id: 5 }; },
  };
  const bookingRepo = {
    async driverOwnsSettlementBooking() { return true; },
    async findSettlementByBookingNumber() {
      return settlementRow({
        commission_status: COMMISSION_STATUS.DUE,
        commission_amount: 120,
      });
    },
  };
  const service = new CommissionSettlementService({}, bookingRepo, driverRepo, {}, {});
  service.reconcileMissingObligationForBooking = async () => { activated = true; };
  const item = await service.getDriverSettlement(44, 'TX202607010001', '/api/v1/driver/settlements');
  assert.equal(activated, true);
  assert.equal(item.commissionStatus, 'PENDING');
});

test('extension MIME mismatch rejected', () => {
  const service = new CommissionSettlementService({}, {}, {}, {}, {});
  assert.throws(
    () => service.validateUploadedFile({
      mimetype: 'image/png',
      originalname: 'receipt.pdf',
    }),
    (err) => err.errorCode === ERROR_CODES.INVALID_FILE_TYPE,
  );
});

test('duplicate rejection does not add review history', async () => {
  let historyLength = 1;
  const bookingRepo = {
    async findSettlementByBookingNumberForUpdate() {
      return settlementRow({
        status: 'SETTLEMENT_PENDING',
        commission_receipt_file_id: null,
        metadata: {
          commissionRejectionReason: 'Blurry photo',
          commissionReviewHistory: [{ action: 'REJECTED', reason: 'Blurry photo' }],
        },
      });
    },
    async findSettlementByBookingNumber() {
      return settlementRow({
        status: 'SETTLEMENT_PENDING',
        commission_receipt_file_id: null,
        metadata: {
          commissionRejectionReason: 'Blurry photo',
          commissionReviewHistory: [{ action: 'REJECTED', reason: 'Blurry photo' }],
        },
      });
    },
    async updateCommissionFields() { historyLength += 1; },
    async insertActivityLog() {},
    async softDelete() {},
  };
  const fileRepo = {
    async softDelete() {},
  };
  const conn = {
    async beginTransaction() {},
    async commit() {},
    async rollback() {},
    release() {},
  };
  const pool = { async getConnection() { return conn; } };
  const service = new CommissionSettlementService(pool, bookingRepo, {}, fileRepo, {});
  await service.reject('TX202607010001', 'Blurry photo', { id: 1, role: ROLES.ADMIN });
  assert.equal(historyLength, 1);
});

test('upload failure does not orphan booking receipt reference', async () => {
  const previousFileId = 99;
  let committed = false;
  const bookingRepo = {
    async findSettlementByBookingNumberForUpdate() {
      return settlementRow({ commission_receipt_file_id: previousFileId });
    },
    async driverOwnsSettlementBooking() { return true; },
    async updateCommissionFields() {},
    async insertActivityLog() {
      throw new Error('activity log failed');
    },
  };
  const driverRepo = {
    async findByUserId() { return { id: 5 }; },
  };
  const fileRepo = {
    async insert(_conn, _data) { return 100; },
    async softDelete() {},
  };
  const conn = {
    async beginTransaction() {},
    async commit() { committed = true; },
    async rollback() {},
    release() {},
  };
  const pool = { async getConnection() { return conn; } };
  const service = new CommissionSettlementService(pool, bookingRepo, driverRepo, fileRepo, {});

  const tmp = path.join(uploadDir, 'test-upload-fail.bin');
  fs.writeFileSync(tmp, 'data');
  await assert.rejects(
    () => service.uploadReceipt(44, 'TX202607010001', {
      path: tmp,
      mimetype: 'application/pdf',
      size: 4,
      originalname: 'receipt.pdf',
    }),
  );
  assert.equal(committed, false);
  if (fs.existsSync(tmp)) fs.unlinkSync(tmp);
  const staged = path.join(uploadDir, 'settlements', 'TX202607010001');
  if (fs.existsSync(staged)) {
    fs.rmSync(staged, { recursive: true, force: true });
  }
});

test('sanitizeDownloadFilename strips unsafe characters', () => {
  const service = new CommissionSettlementService({}, {}, {}, {}, {});
  const name = service.sanitizeDownloadFilename('evil\r\n";.pdf');
  assert.ok(!name.includes('"'));
  assert.ok(!name.includes('\n'));
});

test('receipt file access rejects CUSTOMER', async () => {
  const bookingRepo = {
    async findSettlementByBookingNumber() {
      return settlementRow({ commission_receipt_file_id: 3 });
    },
  };
  const fileRepo = {
    async findById() {
      return { file_path: 'settlements/TX202607010001/test.pdf', mime_type: 'application/pdf' };
    },
  };
  const service = new CommissionSettlementService({}, bookingRepo, {}, fileRepo, {});
  const abs = path.join(uploadDir, 'settlements', 'TX202607010001', 'test.pdf');
  fs.mkdirSync(path.dirname(abs), { recursive: true });
  fs.writeFileSync(abs, '%PDF');

  await assert.rejects(
    () => service.getReceiptFileForActor({ id: 9, role: ROLES.CUSTOMER }, 'TX202607010001', ROLES.CUSTOMER),
    (err) => err.errorCode === ERROR_CODES.FORBIDDEN,
  );
  fs.unlinkSync(abs);
});

test('transaction failure on approve does not write activity log', async () => {
  let activityLogs = 0;
  const bookingRepo = {
    async findSettlementByBookingNumberForUpdate() {
      return settlementRow({ commission_receipt_file_id: 11 });
    },
    async updateCommissionFields() {
      throw new Error('db fail');
    },
    async insertActivityLog() { activityLogs += 1; },
  };
  const conn = {
    async beginTransaction() {},
    async commit() {},
    async rollback() {},
    release() {},
  };
  const pool = { async getConnection() { return conn; } };
  const service = new CommissionSettlementService(pool, bookingRepo, {}, {}, {});

  await assert.rejects(() => service.approve('TX202607010001', { id: 1, role: ROLES.ADMIN }));
  assert.equal(activityLogs, 0);
});

test('admin list reconciles missed obligation before listing', async () => {
  let activateCalls = 0;
  let listQueryAfterReconcile = false;
  const bookingRepo = {
    async findCompletedBookingIdsMissingObligationForAdmin() {
      assert.equal(listQueryAfterReconcile, false);
      return [7];
    },
    async countAdminSettlements() {
      listQueryAfterReconcile = true;
      return 1;
    },
    async findAdminSettlements() {
      return [settlementRow({ commission_status: COMMISSION_STATUS.DUE, commission_amount: 120 })];
    },
  };
  const service = new CommissionSettlementService({}, bookingRepo, {}, {}, {});
  service.activateObligationForCompletedBooking = async (id) => {
    activateCalls += 1;
    assert.equal(id, 7);
  };

  const result = await service.listAdminSettlements({}, '/api/v1/admin/settlements');
  assert.equal(activateCalls, 1);
  assert.equal(listQueryAfterReconcile, true);
  assert.equal(result.items.length, 1);
  assert.equal(result.items[0].commissionStatus, 'PENDING');
});

test('admin list obligation activation is idempotent', async () => {
  let updateCalls = 0;
  let activityLogs = 0;
  const conn = {
    async beginTransaction() {},
    async commit() {},
    async rollback() {},
    release() {},
  };
  const pool = { async getConnection() { return conn; } };
  let obligationState = COMMISSION_STATUS.NOT_DUE_YET;
  let missingIds = [7];
  const bookingRepo = {
    async findCompletedBookingIdsMissingObligationForAdmin() { return missingIds; },
    async countAdminSettlements() { return 1; },
    async findAdminSettlements() {
      return [settlementRow({ commission_status: COMMISSION_STATUS.DUE, commission_amount: 120 })];
    },
    async updateCommissionFields() {
      updateCalls += 1;
      obligationState = COMMISSION_STATUS.DUE;
      missingIds = [];
    },
    async insertActivityLog() { activityLogs += 1; },
  };
  conn.query = async (sql) => {
    if (sql.includes('FOR UPDATE')) {
      return [[{
        id: 7,
        booking_number: 'TX202607010001',
        status: 'COMPLETED',
        total_amount: 1200,
        currency: 'THB',
        commission_status: obligationState,
        commission_amount: obligationState === COMMISSION_STATUS.NOT_DUE_YET ? null : 120,
        completed_at: '2026-07-01 12:00:00',
      }]];
    }
    return [[], []];
  };
  const settingsRepo = {
    async findByGroupAndKey(_g, key) {
      if (key === 'commission_rate_percent') return { value: '10' };
      if (key === 'commission_due_days') return { value: '7' };
      return null;
    },
  };
  const service = new CommissionSettlementService(pool, bookingRepo, {}, {}, settingsRepo);

  await service.listAdminSettlements({}, '/api/v1/admin/settlements');
  obligationState = COMMISSION_STATUS.DUE;
  await service.listAdminSettlements({}, '/api/v1/admin/settlements');

  assert.equal(updateCalls, 1);
  assert.equal(activityLogs, 1);
});

test('admin list uses fixed commission amount when configured', async () => {
  let capturedAmount = null;
  const conn = {
    async beginTransaction() {},
    async commit() {},
    async rollback() {},
    release() {},
    async query(sql) {
      if (sql.includes('FOR UPDATE')) {
        return [[{
          id: 7,
          booking_number: 'TX202607010001',
          status: 'COMPLETED',
          total_amount: 1000,
          currency: 'THB',
          commission_status: COMMISSION_STATUS.NOT_DUE_YET,
          commission_amount: null,
          completed_at: '2026-07-01 12:00:00',
        }]];
      }
      return [[], []];
    },
  };
  const pool = { async getConnection() { return conn; } };
  const bookingRepo = {
    async findCompletedBookingIdsMissingObligationForAdmin() { return [7]; },
    async countAdminSettlements() { return 0; },
    async findAdminSettlements() { return []; },
    async updateCommissionFields(_conn, _id, fields) {
      capturedAmount = fields.commissionAmount;
    },
    async insertActivityLog() {},
  };
  const settingsRepo = {
    async findByGroupAndKey(_g, key) {
      if (key === 'commission_fixed_amount') return { value: '200' };
      if (key === 'commission_due_days') return { value: '5' };
      return null;
    },
  };
  const service = new CommissionSettlementService(pool, bookingRepo, {}, {}, settingsRepo);
  await service.listAdminSettlements({}, '/api/v1/admin/settlements');

  assert.equal(capturedAmount, 200);
});

test('admin list uses configured rate and due days when reconciling', async () => {
  let capturedAmount = null;
  let capturedDueAt = null;
  const conn = {
    async beginTransaction() {},
    async commit() {},
    async rollback() {},
    release() {},
    async query(sql) {
      if (sql.includes('FOR UPDATE')) {
        return [[{
          id: 7,
          booking_number: 'TX202607010001',
          status: 'COMPLETED',
          total_amount: 1000,
          currency: 'THB',
          commission_status: COMMISSION_STATUS.NOT_DUE_YET,
          commission_amount: null,
          completed_at: '2026-07-01 12:00:00',
        }]];
      }
      return [[], []];
    },
  };
  const pool = { async getConnection() { return conn; } };
  const bookingRepo = {
    async findCompletedBookingIdsMissingObligationForAdmin() { return [7]; },
    async countAdminSettlements() { return 0; },
    async findAdminSettlements() { return []; },
    async updateCommissionFields(_conn, _id, fields) {
      capturedAmount = fields.commissionAmount;
      capturedDueAt = fields.commissionDueAt;
    },
    async insertActivityLog() {},
  };
  const settingsRepo = {
    async findByGroupAndKey(_g, key) {
      if (key === 'commission_rate_percent') return { value: '12.5' };
      if (key === 'commission_due_days') return { value: '5' };
      return null;
    },
  };
  const service = new CommissionSettlementService(pool, bookingRepo, {}, {}, settingsRepo);
  await service.listAdminSettlements({}, '/api/v1/admin/settlements');

  assert.equal(capturedAmount, 125);
  assert.ok(capturedDueAt.includes('2026-07-06'));
});

test('admin list does not activate non-completed booking', async () => {
  let updateCalls = 0;
  const conn = {
    async beginTransaction() {},
    async commit() {},
    async rollback() {},
    release() {},
    async query(sql) {
      if (sql.includes('FOR UPDATE')) {
        return [[{
          id: 7,
          booking_number: 'TX202607010001',
          status: 'PICKED_UP',
          total_amount: 1200,
          currency: 'THB',
          commission_status: COMMISSION_STATUS.NOT_DUE_YET,
          commission_amount: null,
          completed_at: null,
        }]];
      }
      return [[], []];
    },
  };
  const pool = { async getConnection() { return conn; } };
  const bookingRepo = {
    async findCompletedBookingIdsMissingObligationForAdmin() { return [7]; },
    async countAdminSettlements() { return 0; },
    async findAdminSettlements() { return []; },
    async updateCommissionFields() { updateCalls += 1; },
    async insertActivityLog() {},
  };
  const service = new CommissionSettlementService(pool, bookingRepo, {}, {}, {
    async findByGroupAndKey() { return { value: '10' }; },
  });

  await service.listAdminSettlements({}, '/api/v1/admin/settlements');
  assert.equal(updateCalls, 0);
});

test('admin list preserves pagination and filters after reconciliation', async () => {
  let capturedFilters = null;
  let capturedPagination = null;
  const bookingRepo = {
    async findCompletedBookingIdsMissingObligationForAdmin(filters) {
      capturedFilters = filters;
      return [];
    },
    async countAdminSettlements(filters) {
      assert.equal(filters.driverId, 5);
      return 2;
    },
    async findAdminSettlements(filters, pagination) {
      capturedPagination = pagination;
      assert.equal(filters.driverId, 5);
      return [
        settlementRow({ booking_number: 'TX202607010001' }),
        settlementRow({ booking_number: 'TX202607010002' }),
      ];
    },
  };
  const service = new CommissionSettlementService({}, bookingRepo, {}, {}, {});

  const result = await service.listAdminSettlements({
    driverId: '5',
    page: '2',
    limit: '10',
  }, '/api/v1/admin/settlements');

  assert.equal(capturedFilters.driverId, 5);
  assert.equal(capturedPagination.page, 2);
  assert.equal(capturedPagination.limit, 10);
  assert.equal(capturedPagination.offset, 10);
  assert.equal(result.total, 2);
  assert.equal(result.page, 2);
  assert.equal(result.pageSize, 10);
  assert.equal(result.items.length, 2);
});

test('admin list reconciliation failure does not block other obligations or listing', async () => {
  const activated = [];
  const bookingRepo = {
    async findCompletedBookingIdsMissingObligationForAdmin() { return [7, 8]; },
    async countAdminSettlements() { return 1; },
    async findAdminSettlements() {
      return [settlementRow({ id: 8, booking_number: 'TX202607010002' })];
    },
  };
  const service = new CommissionSettlementService({}, bookingRepo, {}, {}, {});
  service.activateObligationForCompletedBooking = async (id) => {
    if (id === 7) throw new Error('db fail');
    activated.push(id);
  };

  const result = await service.listAdminSettlements({}, '/api/v1/admin/settlements');
  assert.deepEqual(activated, [8]);
  assert.equal(result.items.length, 1);
});

test('admin list reconciliation failure does not create partial obligation', async () => {
  let updateCalls = 0;
  let rolledBack = false;
  const conn = {
    async beginTransaction() {},
    async commit() {},
    async rollback() { rolledBack = true; },
    release() {},
    async query(sql) {
      if (sql.includes('FOR UPDATE')) {
        return [[{
          id: 7,
          booking_number: 'TX202607010001',
          status: 'COMPLETED',
          total_amount: 1200,
          currency: 'THB',
          commission_status: COMMISSION_STATUS.NOT_DUE_YET,
          commission_amount: null,
          completed_at: '2026-07-01 12:00:00',
        }]];
      }
      return [[], []];
    },
  };
  const pool = { async getConnection() { return conn; } };
  const bookingRepo = {
    async findCompletedBookingIdsMissingObligationForAdmin() { return [7]; },
    async countAdminSettlements() { return 0; },
    async findAdminSettlements() { return []; },
    async updateCommissionFields() {
      updateCalls += 1;
      throw new Error('db fail');
    },
    async insertActivityLog() {},
  };
  const settingsRepo = {
    async findByGroupAndKey(_g, key) {
      if (key === 'commission_rate_percent') return { value: '10' };
      if (key === 'commission_due_days') return { value: '7' };
      return null;
    },
  };
  const service = new CommissionSettlementService(pool, bookingRepo, {}, {}, settingsRepo);

  await service.listAdminSettlements({}, '/api/v1/admin/settlements');
  assert.equal(updateCalls, 1);
  assert.equal(rolledBack, true);
});
