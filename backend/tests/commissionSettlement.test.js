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
const BookingRepository = require('../src/repositories/booking.repository');
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

test('admin settlement repository excludes paid settlements by default', () => {
  const repository = new BookingRepository({});

  const defaultFilters = repository.buildAdminSettlementFilters({});
  const approvedFilters = repository.buildAdminSettlementFilters({ status: 'APPROVED' });

  assert.match(defaultFilters.whereSql, /b\.commission_status <> 'PAID'/);
  assert.doesNotMatch(approvedFilters.whereSql, /b\.commission_status <> 'PAID'/);
  assert.match(approvedFilters.whereSql, /b\.commission_status = 'PAID'/);
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

test('manual approval without receipt marks settlement paid and records audit metadata', async () => {
  let savedFields = null;
  let activityLog = null;
  let transitionRequest = null;
  let outboxPayload = null;
  const bookingRepo = {
    async findSettlementByBookingNumberForUpdate() {
      return settlementRow({
        status: 'SETTLEMENT_PENDING',
        commission_receipt_file_id: null,
        commission_status: COMMISSION_STATUS.DUE,
        commission_amount: 200,
      });
    },
    async updateCommissionFields(_conn, _id, fields) {
      savedFields = fields;
    },
    async insertActivityLog(_conn, _id, log) {
      activityLog = log;
    },
    async findSettlementByBookingNumber() {
      return settlementRow({
        status: 'COMPLETED',
        commission_status: COMMISSION_STATUS.PAID,
        commission_amount: 200,
        commission_paid_at: savedFields.commissionPaidAt,
        metadata: savedFields.metadata,
      });
    },
  };
  const conn = {
    async beginTransaction() {},
    async commit() {},
    async rollback() {},
    release() {},
    async query() {
      return [[{ driver_id: 5, driver_user_id: 44 }]];
    },
  };
  const service = new CommissionSettlementService(
    { async getConnection() { return conn; } },
    bookingRepo,
    {},
    {},
    {},
    {
      async insertNotificationEvent(_conn, event) {
        outboxPayload = event.payload;
        return 77;
      },
    },
    { async dispatchOutboxIds() {} },
    {
      async transitionInTransaction(_conn, bookingNumber, request) {
        transitionRequest = { bookingNumber, request };
        return { outboxId: 88, domainEvent: null, eventPayload: null };
      },
      async dispatchOutboxAfterCommit() {},
      emitDomainEvent() {},
    },
  );

  const result = await service.manualApproveWithoutReceipt(
    'TX202607010001',
    'Bank transfer confirmed by administrator',
    { id: 1, role: ROLES.SUPER_ADMIN },
  );

  assert.equal(savedFields.commissionStatus, COMMISSION_STATUS.PAID);
  assert.equal(savedFields.metadata.commissionApprovalMode, 'MANUAL_WITHOUT_RECEIPT');
  assert.equal(savedFields.metadata.commissionApprovalNote, 'Bank transfer confirmed by administrator');
  assert.equal(savedFields.metadata.commissionApprovedByUserId, 1);
  assert.equal(savedFields.metadata.commissionReceiptMissingAtApproval, true);
  assert.equal(activityLog.activityType, 'MANUAL_SETTLEMENT_APPROVED_WITHOUT_RECEIPT');
  assert.equal(activityLog.payload.approvalMode, 'MANUAL_WITHOUT_RECEIPT');
  assert.equal(transitionRequest.request.status, 'COMPLETED');
  assert.equal(outboxPayload.approvalMode, 'MANUAL_WITHOUT_RECEIPT');
  assert.equal(result.commissionStatus, 'APPROVED');
  assert.equal(result.approval.mode, 'MANUAL_WITHOUT_RECEIPT');
});

test('manual approval requires a note', async () => {
  const service = new CommissionSettlementService({}, {}, {}, {}, {});
  await assert.rejects(
    () => service.manualApproveWithoutReceipt(
      'TX202607010001',
      '   ',
      { id: 1, role: ROLES.ADMIN },
    ),
    (err) => err.errorCode === ERROR_CODES.ADMIN_APPROVAL_NOTE_REQUIRED,
  );
});

test('manual approval is rejected when a receipt exists', async () => {
  const bookingRepo = {
    async findSettlementByBookingNumberForUpdate() {
      return settlementRow({
        status: 'SETTLEMENT_PENDING',
        commission_receipt_file_id: 42,
        receipt_mime_type: 'image/png',
        commission_status: COMMISSION_STATUS.DUE,
      });
    },
  };
  const conn = {
    async beginTransaction() {},
    async commit() {},
    async rollback() {},
    release() {},
  };
  const service = new CommissionSettlementService(
    { async getConnection() { return conn; } },
    bookingRepo,
    {},
    {},
    {},
  );

  await assert.rejects(
    () => service.manualApproveWithoutReceipt(
      'TX202607010001',
      'Confirmed elsewhere',
      { id: 1, role: ROLES.ADMIN },
    ),
    (err) => err.errorCode === ERROR_CODES.SETTLEMENT_MANUAL_APPROVAL_NOT_ALLOWED,
  );
});

test('manual approval rejects already approved settlements with 409 code', async () => {
  const bookingRepo = {
    async findSettlementByBookingNumberForUpdate() {
      return settlementRow({
        status: 'COMPLETED',
        commission_status: COMMISSION_STATUS.PAID,
      });
    },
  };
  const conn = {
    async beginTransaction() {},
    async commit() {},
    async rollback() {},
    release() {},
  };
  const service = new CommissionSettlementService(
    { async getConnection() { return conn; } },
    bookingRepo,
    {},
    {},
    {},
  );

  await assert.rejects(
    () => service.manualApproveWithoutReceipt(
      'TX202607010001',
      'Confirmed elsewhere',
      { id: 1, role: ROLES.ADMIN },
    ),
    (err) => err.statusCode === 409
      && err.errorCode === ERROR_CODES.SETTLEMENT_ALREADY_APPROVED,
  );
});

test('manual approve endpoint requires admin role and note body', async () => {
  const driverRes = await request(app)
    .post('/api/v1/admin/settlements/TX202607010001/manual-approve')
    .set('Authorization', `Bearer ${sign('DRIVER', 44)}`)
    .send({ note: 'confirmed' });
  assert.equal(driverRes.status, 403);

  const adminRes = await request(app)
    .post('/api/v1/admin/settlements/TX202607010001/manual-approve')
    .set('Authorization', `Bearer ${sign('ADMIN', 1)}`)
    .send({});
  assert.equal(adminRes.status, 400);
});

test('manual approve endpoint rejects inactive admin token', async () => {
  container.register('userRepository', () => ({
    async findById() {
      return {
        id: 1,
        email: 'admin@example.com',
        role: ROLES.ADMIN,
        is_active: 0,
      };
    },
  }));
  container.register('commissionSettlementService', () => ({
    async manualApproveWithoutReceipt() {
      throw new Error('manual approval should not be reached');
    },
  }));

  const res = await request(app)
    .post('/api/v1/admin/settlements/TX202607010001/manual-approve')
    .set('Authorization', `Bearer ${sign('ADMIN', 1)}`)
    .send({ note: 'confirmed in bank account' });

  assert.equal(res.status, 403);
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

test('rejected settlement blocks assignment until a new slip is accepted', async () => {
  const bookingRepo = {
    async findUnpaidSettlementsForDriver() {
      return [{
        commission_status: COMMISSION_STATUS.DUE,
        commission_due_at: null,
        commission_receipt_file_id: null,
        metadata: { commissionRejectionReason: 'Unreadable transfer slip' },
      }];
    },
  };
  const service = new CommissionSettlementService({}, bookingRepo, {}, {}, {});
  const blocked = await service.driverHasBlockingSettlement(5);
  assert.equal(blocked, true);
});

test('settled or absent settlement does not block assignment', async () => {
  const noSettlement = new CommissionSettlementService(
    {},
    { async findUnpaidSettlementsForDriver() { return []; } },
    {},
    {},
    {},
  );
  assert.equal(await noSettlement.driverHasBlockingSettlement(5), false);

  const settled = new CommissionSettlementService(
    {},
    {
      async findUnpaidSettlementsForDriver() {
        return [{
          commission_status: COMMISSION_STATUS.PAID,
          commission_due_at: null,
          commission_receipt_file_id: 42,
          metadata: null,
        }];
      },
    },
    {},
    {},
    {},
  );
  assert.equal(await settled.driverHasBlockingSettlement(5), false);
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
  assert.equal(item.customerPaymentAmount, 1200);
  assert.equal(item.customerPaymentCurrency, 'THB');
  assert.equal(item.customerTotalAmount, 1200);
  assert.equal(item.customerTotalCurrency, 'THB');
  assert.equal(item.companyCommissionAmount, 120);
  assert.equal(item.companyCommissionCurrency, 'THB');
  assert.equal(item.driverExpectedIncomeAmount, 1080);
  assert.equal(item.driverExpectedIncomeCurrency, 'THB');

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
  assert.equal(nullItem.driverExpectedIncomeAmount, 1080);
});

test('mapSettlementListItem keeps unknown income nullable when commission is unknown', () => {
  const service = new CommissionSettlementService({}, {}, {}, {}, {});
  const item = service.mapSettlementListItem(
    settlementRow({ commission_amount: null }),
    '/api/v1/driver/settlements',
    ROLES.DRIVER,
  );
  assert.equal(item.customerPaymentAmount, 1200);
  assert.equal(item.companyCommissionAmount, null);
  assert.equal(item.companyCommissionCurrency, null);
  assert.equal(item.driverExpectedIncomeAmount, null);
  assert.equal(item.driverExpectedIncomeCurrency, null);
});

test('mapSettlementListItem exposes public status and blocking policy consistently', () => {
  const service = new CommissionSettlementService({}, {}, {}, {}, {});
  const map = (overrides) =>
    service.mapSettlementListItem(
      settlementRow(overrides),
      '/api/v1/driver/settlements',
      ROLES.DRIVER,
    );

  const notDue = map({ commission_status: COMMISSION_STATUS.NOT_DUE_YET });
  assert.equal(notDue.commissionStatus, 'NOT_DUE_YET');
  assert.equal(notDue.blocksNewCalls, false);

  const waived = map({ commission_status: COMMISSION_STATUS.WAIVED });
  assert.equal(waived.commissionStatus, 'WAIVED');
  assert.equal(waived.blocksNewCalls, false);

  const due = map({ commission_status: COMMISSION_STATUS.DUE });
  assert.equal(due.commissionStatus, 'DUE');
  assert.equal(due.blocksNewCalls, true);

  const overdue = map({ commission_status: COMMISSION_STATUS.OVERDUE });
  assert.equal(overdue.commissionStatus, 'OVERDUE');
  assert.equal(overdue.blocksNewCalls, true);

  const submitted = map({
    commission_status: COMMISSION_STATUS.DUE,
    commission_receipt_file_id: 42,
    receipt_mime_type: 'image/png',
  });
  assert.equal(submitted.commissionStatus, 'RECEIPT_SUBMITTED');
  assert.equal(submitted.blocksNewCalls, true);

  const rejected = map({
    commission_status: COMMISSION_STATUS.DUE,
    metadata: { commissionRejectionReason: 'blurred' },
  });
  assert.equal(rejected.commissionStatus, 'REJECTED');
  assert.equal(rejected.blocksNewCalls, true);

  const approved = map({ commission_status: COMMISSION_STATUS.PAID });
  assert.equal(approved.commissionStatus, 'APPROVED');
  assert.equal(approved.blocksNewCalls, false);
});

test('driverExpectedIncome never returns unsafe negative income', () => {
  const service = new CommissionSettlementService({}, {}, {}, {}, {});
  assert.equal(service.driverExpectedIncome(settlementRow({
    total_amount: 1300,
    commission_amount: 200,
  })), 1100);
  assert.equal(service.driverExpectedIncome(settlementRow({
    total_amount: 1300,
    commission_amount: 0,
  })), 1300);
  assert.equal(service.driverExpectedIncome(settlementRow({
    total_amount: null,
    commission_amount: 200,
  })), null);
  assert.equal(service.driverExpectedIncome(settlementRow({
    total_amount: 1300,
    commission_amount: null,
  })), null);
  assert.equal(service.driverExpectedIncome(settlementRow({
    total_amount: 1300,
    commission_amount: 1500,
  })), null);
  assert.equal(service.driverExpectedIncome(settlementRow({
    total_amount: -1,
    commission_amount: 0,
  })), null);
  assert.equal(service.driverExpectedIncome(settlementRow({
    total_amount: 1300,
    commission_amount: -1,
  })), null);
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
  assert.equal(item.canApprove, false);
});

test('admin settlement list item exposes receipt and approval when file linked', () => {
  const service = new CommissionSettlementService({}, {}, {}, {}, {});
  const item = service.mapSettlementListItem(
    settlementRow({
      status: 'SETTLEMENT_PENDING',
      commission_receipt_file_id: 42,
      metadata: { commissionReceiptSubmittedAt: '2026-07-12T04:00:00.000Z' },
      receipt_mime_type: 'image/png',
    }),
    '/api/v1/admin/settlements',
    ROLES.ADMIN,
  );
  assert.equal(item.commissionStatus, 'RECEIPT_SUBMITTED');
  assert.equal(item.receiptStatus, 'RECEIPT_SUBMITTED');
  assert.equal(item.receiptFileId, 42);
  assert.equal(item.canApprove, true);
  assert.equal(item.receiptUrl, '/api/v1/admin/settlements/TX202607010001/receipt');
});

test('orphaned commission_receipt_file_id without files row is not submitted', () => {
  const service = new CommissionSettlementService({}, {}, {}, {}, {});
  const item = service.mapSettlementListItem(
    settlementRow({
      status: 'SETTLEMENT_PENDING',
      commission_receipt_file_id: 99,
      receipt_mime_type: null,
      receipt_original_filename: null,
      receipt_file_size: null,
    }),
    '/api/v1/admin/settlements',
    ROLES.ADMIN,
  );
  assert.equal(item.commissionStatus, 'DUE');
  assert.equal(item.receiptStatus, 'NONE');
  assert.equal(item.receiptFileId, undefined);
  assert.equal(item.canApprove, false);
});

test('uploadReceipt persists receipt and returns RECEIPT_SUBMITTED', async () => {
  let savedFileId = null;
  let savedMetadata = null;
  const bookingRepo = {
    async findSettlementByBookingNumberForUpdate() {
      return settlementRow({
        status: 'SETTLEMENT_PENDING',
        commission_receipt_file_id: null,
      });
    },
    async driverOwnsSettlementBooking() { return true; },
    async updateCommissionFields(_conn, _id, fields) {
      savedFileId = fields.commissionReceiptFileId;
      savedMetadata = fields.metadata;
    },
    async insertActivityLog() {},
    async findSettlementByBookingNumber() {
      return settlementRow({
        status: 'SETTLEMENT_PENDING',
        commission_receipt_file_id: savedFileId,
        metadata: savedMetadata,
        receipt_mime_type: 'application/pdf',
        receipt_original_filename: 'receipt.pdf',
      });
    },
  };
  const driverRepo = {
    async findByUserId() { return { id: 5 }; },
  };
  const fileRepo = {
    async insert() { return 501; },
    async softDelete() {},
  };
  const conn = {
    async beginTransaction() {},
    async commit() {},
    async rollback() {},
    release() {},
  };
  const pool = { async getConnection() { return conn; } };
  const service = new CommissionSettlementService(pool, bookingRepo, driverRepo, fileRepo, {});

  const tmp = path.join(uploadDir, 'test-upload-success.bin');
  fs.writeFileSync(tmp, '%PDF');
  const result = await service.uploadReceipt(44, 'TX202607010001', {
    path: tmp,
    mimetype: 'application/pdf',
    size: 4,
    originalname: 'receipt.pdf',
  });

  assert.equal(savedFileId, 501);
  assert.ok(savedMetadata.commissionReceiptSubmittedAt);
  assert.equal(result.commissionStatus, 'RECEIPT_SUBMITTED');
  assert.equal(result.receiptStatus, 'RECEIPT_SUBMITTED');
  assert.equal(result.receiptFileId, 501);
  assert.equal(result.receiptUrl, '/api/v1/driver/settlements/TX202607010001/receipt');
  if (fs.existsSync(tmp)) fs.unlinkSync(tmp);
  const staged = path.join(uploadDir, 'settlements', 'TX202607010001');
  if (fs.existsSync(staged)) {
    fs.rmSync(staged, { recursive: true, force: true });
  }
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
  const settingsRepository = {
    async findByGroup(groupName) {
      assert.equal(groupName, 'operations');
      return [
        { key_name: 'bankName', value: 'SCB' },
        { key_name: 'accountName', value: 'T-Ride Ops' },
        { key_name: 'accountNumber', value: '1234567890' },
        { key_name: 'promptPayNumber', value: '0999999999' },
        { key_name: 'promptPayQrImagePath', value: 'settings/promptpay.png' },
      ];
    },
  };
  const service = new CommissionSettlementService({}, bookingRepo, driverRepo, {}, settingsRepository);
  service.reconcileMissingObligationForBooking = async () => { activated = true; };
  const item = await service.getDriverSettlement(44, 'TX202607010001', '/api/v1/driver/settlements');
  assert.equal(activated, true);
  assert.equal(item.commissionStatus, 'DUE');
  assert.match(
    item.paymentInstructions.promptPayQrImageUrl,
    /^\/api\/v1\/settings\/assets\/promptPayQr\?v=[a-f0-9]{12}$/,
  );
  assert.deepEqual(item.paymentInstructions, {
    bankName: 'SCB',
    accountName: 'T-Ride Ops',
    accountNumber: '1234567890',
    promptPayNumber: '0999999999',
    promptPayQrImageUrl: item.paymentInstructions.promptPayQrImageUrl,
  });
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
  let rolledBack = false;
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
    async rollback() { rolledBack = true; },
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
  assert.equal(rolledBack, true);
  if (fs.existsSync(tmp)) fs.unlinkSync(tmp);
  const staged = path.join(uploadDir, 'settlements', 'TX202607010001');
  assert.deepEqual(fs.existsSync(staged) ? fs.readdirSync(staged) : [], []);
  if (fs.existsSync(staged)) {
    fs.rmSync(staged, { recursive: true, force: true });
  }
});

test('post-commit reload failure preserves committed receipt file', async () => {
  let savedFileId = null;
  let committed = false;
  let rolledBack = false;
  const bookingRepo = {
    async findSettlementByBookingNumberForUpdate() {
      return settlementRow({ commission_receipt_file_id: null });
    },
    async driverOwnsSettlementBooking() { return true; },
    async updateCommissionFields(_conn, _id, fields) {
      savedFileId = fields.commissionReceiptFileId;
    },
    async insertActivityLog() {},
    async findSettlementByBookingNumber() {
      throw new Error('post-commit reload failed');
    },
  };
  const driverRepo = {
    async findByUserId() { return { id: 5 }; },
  };
  const fileRepo = {
    async insert() { return 502; },
    async softDelete() {},
  };
  const conn = {
    async beginTransaction() {},
    async commit() { committed = true; },
    async rollback() { rolledBack = true; },
    release() {},
  };
  const service = new CommissionSettlementService(
    { async getConnection() { return conn; } },
    bookingRepo,
    driverRepo,
    fileRepo,
    {},
  );
  const tmp = path.join(uploadDir, 'test-upload-post-commit.bin');
  fs.writeFileSync(tmp, '%PDF');

  await assert.rejects(
    () => service.uploadReceipt(44, 'TX202607010001', {
      path: tmp,
      mimetype: 'application/pdf',
      size: 4,
      originalname: 'receipt.pdf',
    }),
    /post-commit reload failed/,
  );

  const staged = path.join(uploadDir, 'settlements', 'TX202607010001');
  assert.equal(savedFileId, 502);
  assert.equal(committed, true);
  assert.equal(rolledBack, false);
  assert.equal(fs.readdirSync(staged).length, 1);
  fs.rmSync(staged, { recursive: true, force: true });
  if (fs.existsSync(tmp)) fs.unlinkSync(tmp);
});

test('absorbed post-commit outbox failure keeps receipt and returns success', async () => {
  let savedFileId = null;
  const bookingRepo = {
    async findSettlementByBookingNumberForUpdate() {
      return settlementRow({ commission_receipt_file_id: null });
    },
    async driverOwnsSettlementBooking() { return true; },
    async updateCommissionFields(_conn, _id, fields) {
      savedFileId = fields.commissionReceiptFileId;
    },
    async insertActivityLog() {},
    async findSettlementByBookingNumber() {
      return settlementRow({
        commission_receipt_file_id: savedFileId,
        receipt_mime_type: 'application/pdf',
        receipt_original_filename: 'receipt.pdf',
      });
    },
  };
  const conn = {
    async beginTransaction() {},
    async commit() {},
    async rollback() { throw new Error('rollback must not run'); },
    release() {},
  };
  const service = new CommissionSettlementService(
    { async getConnection() { return conn; } },
    bookingRepo,
    { async findByUserId() { return { id: 5 }; } },
    { async insert() { return 503; }, async softDelete() {} },
    {},
    { async insertNotificationEvent() { return 77; } },
    { async dispatchOutboxIds() {} },
  );
  const tmp = path.join(uploadDir, 'test-upload-outbox.bin');
  fs.writeFileSync(tmp, '%PDF');

  const result = await service.uploadReceipt(44, 'TX202607010001', {
    path: tmp,
    mimetype: 'application/pdf',
    size: 4,
    originalname: 'receipt.pdf',
  });

  const staged = path.join(uploadDir, 'settlements', 'TX202607010001');
  assert.equal(result.receiptFileId, 503);
  assert.equal(fs.readdirSync(staged).length, 1);
  fs.rmSync(staged, { recursive: true, force: true });
  if (fs.existsSync(tmp)) fs.unlinkSync(tmp);
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
  assert.equal(result.items[0].commissionStatus, 'DUE');
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
