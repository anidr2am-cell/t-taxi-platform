process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const fs = require('fs');
const path = require('path');
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { EVENTS } = require('../src/events');
const { uploadDir } = require('../src/config/multer');

const ERROR_CODES = require('../src/constants/errorCodes');
const COMMISSION_STATUS = require('../src/constants/commissionStatus');
const ROLES = require('../src/constants/roles');
const CommissionSettlementService = require('../src/services/commissionSettlement.service');

const BOOKING_NUMBER = 'TX202607010001';
const ADMIN_A = { id: 1, role: ROLES.ADMIN };
const ADMIN_B = { id: 2, role: ROLES.SUPER_ADMIN };

function sqlDateFromNow(days) {
  return new Date(Date.now() + days * 86400000).toISOString().slice(0, 19).replace('T', ' ');
}

function settlementRow(overrides = {}) {
  return {
    id: 7,
    booking_number: BOOKING_NUMBER,
    status: 'SETTLEMENT_PENDING',
    completed_at: '2026-07-01 12:00:00',
    total_amount: 1200,
    currency: 'THB',
    commission_status: COMMISSION_STATUS.DUE,
    commission_amount: 200,
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

function cloneMetadata(value) {
  if (value == null) return null;
  return JSON.parse(JSON.stringify(value));
}

function createRowLockHarness(initialRow, options = {}) {
  let row = settlementRow(initialRow);
  let locked = false;
  const waiters = [];
  const assignmentDriver = {
    driver_id: Object.hasOwn(options, 'assignmentDriverId')
      ? options.assignmentDriverId
      : (row.driver_id ?? 5),
    driver_user_id: Object.hasOwn(options, 'assignmentDriverUserId')
      ? options.assignmentDriverUserId
      : 44,
  };
  const counts = {
    activityLogs: [],
    outboxEvents: [],
    transitions: 0,
    completeActiveAssignment: 0,
    updateCommission: 0,
    rollbacks: 0,
    commits: 0,
    obligationActivities: [],
    obligationOutbox: [],
  };

  async function acquireRowLock() {
    if (locked) {
      await new Promise((resolve) => waiters.push(resolve));
    }
    locked = true;
  }

  function releaseRowLock() {
    locked = false;
    const next = waiters.shift();
    if (next) next();
  }

  function createConn() {
    let inTxn = false;
    return {
      async beginTransaction() {
        inTxn = true;
      },
      async commit() {
        counts.commits += 1;
        if (inTxn) releaseRowLock();
        inTxn = false;
      },
      async rollback() {
        counts.rollbacks += 1;
        if (inTxn) releaseRowLock();
        inTxn = false;
      },
      release() {},
      async query() {
        return [[], []];
      },
    };
  }

  const pool = {
    async getConnection() {
      return createConn();
    },
  };

  const bookingRepo = {
    async findSettlementByBookingNumberForUpdate() {
      await acquireRowLock();
      return {
        ...row,
        metadata: cloneMetadata(row.metadata),
      };
    },
    async findSettlementByBookingNumber() {
      return {
        ...row,
        metadata: cloneMetadata(row.metadata),
      };
    },
    async findByBookingNumberForUpdate() {
      await acquireRowLock();
      return {
        id: row.id,
        booking_number: row.booking_number,
        status: row.status,
        driver_id: row.driver_id,
        driver_user_id: 44,
      };
    },
    async updateStatus(_conn, _id, status) {
      row = { ...row, status };
    },
    async updateCommissionFields(_conn, _id, fields) {
      counts.updateCommission += 1;
      const next = {
        ...row,
        commission_status: fields.commissionStatus ?? row.commission_status,
        commission_amount: fields.commissionAmount ?? row.commission_amount,
        commission_paid_at: fields.commissionPaidAt ?? row.commission_paid_at,
        commission_receipt_file_id: fields.commissionReceiptFileId ?? row.commission_receipt_file_id,
        metadata: fields.metadata ?? row.metadata,
      };
      if (fields.commissionReceiptFileId != null) {
        next.receipt_mime_type = 'application/pdf';
        next.receipt_original_filename = 'slip.pdf';
        next.receipt_file_size = 8;
      }
      row = next;
    },
    async insertActivityLog(_conn, _id, log) {
      counts.activityLogs.push(log);
    },
    async insertStatusLog() {},
    async completeActiveAssignment() {
      counts.completeActiveAssignment += 1;
    },
    async driverOwnsSettlementBooking() {
      return true;
    },
    async findSettlementNotificationDriver(_conn, bookingId) {
      if (bookingId !== row.id) return null;
      if (!assignmentDriver.driver_id || !assignmentDriver.driver_user_id) {
        return null;
      }
      return { ...assignmentDriver };
    },
  };

  const outboxRepository = {
    async insertNotificationEvent(_conn, event) {
      counts.outboxEvents.push(event);
      return counts.outboxEvents.length;
    },
  };

  const bookingStatusService = {
    async transitionInTransaction(_conn, _bookingNumber, request) {
      counts.transitions += 1;
      row = { ...row, status: request.status };
      await bookingRepo.completeActiveAssignment();
      return {
        outboxId: 900 + counts.transitions,
        domainEvent: EVENTS.TRIP_COMPLETED,
        eventPayload: { bookingId: row.id, bookingNumber: row.booking_number },
      };
    },
    async dispatchOutboxAfterCommit() {},
    emitDomainEvent() {},
  };

  const service = new CommissionSettlementService(
    pool,
    bookingRepo,
    {
      async findByUserId() {
        return { id: 5 };
      },
    },
    {
      async insert() { return 501; },
      async softDelete() {},
    },
    {},
    outboxRepository,
    { async dispatchOutboxIds() {} },
    bookingStatusService,
  );

  return {
    service,
    counts,
    getRow: () => row,
    setRow: (patch) => {
      row = { ...row, ...patch };
    },
    bookingRepo,
    pool,
    bookingStatusService,
    outboxRepository,
    assignmentDriver,
  };
}

function createActivationHarness(bookingState) {
  let updateCalls = 0;
  let activityLogs = 0;
  let outboxInserts = 0;
  const conn = {
    async beginTransaction() {},
    async commit() {},
    async rollback() {},
    release() {},
    async query(sql) {
      if (sql.includes('FOR UPDATE') && sql.includes('FROM bookings')) {
        return [[{ ...bookingState }]];
      }
      return [[], []];
    },
  };
  const pool = { async getConnection() { return conn; } };
  const bookingRepo = {
    async updateCommissionFields() { updateCalls += 1; },
    async insertActivityLog() { activityLogs += 1; },
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
    {
      async findByIdForUpdate() {
        return { id: 5, user_id: 44 };
      },
    },
    {},
    settingsRepo,
    {
      async insertNotificationEvent() {
        outboxInserts += 1;
        return outboxInserts;
      },
    },
    { async dispatchOutboxIds() {} },
  );
  return {
    service,
    getCounts: () => ({ updateCalls, activityLogs, outboxInserts }),
  };
}

test('manual approval genuine retry replays current detail without side effects', async () => {
  let activityLogs = 0;
  const bookingRepo = {
    async findSettlementByBookingNumberForUpdate() {
      return settlementRow({
        status: 'COMPLETED',
        commission_status: COMMISSION_STATUS.PAID,
        commission_paid_at: '2026-07-02 10:00:00',
        metadata: {
          commissionApprovalMode: 'MANUAL_WITHOUT_RECEIPT',
          commissionApprovalNote: 'Bank confirmed',
          commissionApprovedByUserId: 1,
        },
      });
    },
    async findSettlementByBookingNumber() {
      return settlementRow({
        status: 'COMPLETED',
        commission_status: COMMISSION_STATUS.PAID,
        commission_paid_at: '2026-07-02 10:00:00',
        metadata: {
          commissionApprovalMode: 'MANUAL_WITHOUT_RECEIPT',
          commissionApprovalNote: 'Bank confirmed',
          commissionApprovedByUserId: 1,
          commissionReviewHistory: [{
            action: 'APPROVED',
            approvalMode: 'MANUAL_WITHOUT_RECEIPT',
          }],
        },
      });
    },
    async updateCommissionFields() {
      throw new Error('must not update on replay');
    },
    async insertActivityLog() { activityLogs += 1; },
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

  const result = await service.manualApproveWithoutReceipt(
    BOOKING_NUMBER,
    'Different note on retry',
    ADMIN_A,
  );

  assert.equal(activityLogs, 0);
  assert.equal(result.commissionStatus, 'APPROVED');
  assert.equal(result.approval.mode, 'MANUAL_WITHOUT_RECEIPT');
});

test('manual approval retry stays 409 when prior success was receipt verified', async () => {
  const bookingRepo = {
    async findSettlementByBookingNumberForUpdate() {
      return settlementRow({
        status: 'COMPLETED',
        commission_status: COMMISSION_STATUS.PAID,
        commission_receipt_file_id: 11,
        receipt_mime_type: 'image/png',
        metadata: { commissionApprovalMode: 'RECEIPT_VERIFIED' },
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
    () => service.manualApproveWithoutReceipt(BOOKING_NUMBER, 'Retry', ADMIN_A),
    (err) => err.errorCode === ERROR_CODES.SETTLEMENT_ALREADY_APPROVED
      && err.statusCode === 409,
  );
});

test('concurrent manual approvals serialize and second returns replay', async () => {
  const harness = createRowLockHarness({
    status: 'SETTLEMENT_PENDING',
    commission_receipt_file_id: null,
    commission_status: COMMISSION_STATUS.DUE,
    commission_amount: 200,
  });

  const results = await Promise.all([
    harness.service.manualApproveWithoutReceipt(BOOKING_NUMBER, 'Admin A confirmed', ADMIN_A),
    harness.service.manualApproveWithoutReceipt(BOOKING_NUMBER, 'Admin B confirmed', ADMIN_B),
  ]);

  assert.equal(harness.counts.updateCommission, 1);
  assert.equal(harness.counts.transitions, 1);
  assert.equal(harness.counts.completeActiveAssignment, 1);
  assert.equal(
    harness.counts.activityLogs.filter(
      (log) => log.activityType === 'MANUAL_SETTLEMENT_APPROVED_WITHOUT_RECEIPT',
    ).length,
    1,
  );
  assert.equal(
    harness.counts.outboxEvents.filter((event) => event.eventType === EVENTS.SETTLEMENT_APPROVED).length,
    1,
  );
  assert.equal(results[0].approval.mode, 'MANUAL_WITHOUT_RECEIPT');
  assert.equal(results[1].approval.mode, 'MANUAL_WITHOUT_RECEIPT');
  assert.equal(harness.getRow().status, 'COMPLETED');
  assert.equal(harness.getRow().commission_status, COMMISSION_STATUS.PAID);

  const reviewHistory = harness.getRow().metadata?.commissionReviewHistory ?? [];
  assert.equal(reviewHistory.length, 1);
  assert.equal(reviewHistory[0].approvalMode, 'MANUAL_WITHOUT_RECEIPT');
});

test('concurrent receipt approvals serialize with exactly-once side effects', async () => {
  const harness = createRowLockHarness({
    status: 'SETTLEMENT_PENDING',
    commission_receipt_file_id: 11,
    receipt_mime_type: 'image/png',
    commission_status: COMMISSION_STATUS.DUE,
  });

  const results = await Promise.all([
    harness.service.approve(BOOKING_NUMBER, ADMIN_A),
    harness.service.approve(BOOKING_NUMBER, ADMIN_B),
  ]);

  assert.equal(harness.counts.updateCommission, 1);
  assert.equal(harness.counts.transitions, 1);
  assert.equal(harness.counts.completeActiveAssignment, 1);
  assert.equal(
    harness.counts.activityLogs.filter((log) => log.activityType === 'COMMISSION_APPROVED').length,
    1,
  );
  assert.equal(
    harness.counts.outboxEvents.filter((event) => event.eventType === EVENTS.SETTLEMENT_APPROVED).length,
    1,
  );
  assert.equal(results[0].commissionStatus, 'APPROVED');
  assert.equal(results[1].commissionStatus, 'APPROVED');
  assert.equal(harness.getRow().status, 'COMPLETED');
  assert.equal(harness.getRow().commission_status, COMMISSION_STATUS.PAID);

  const reviewHistory = harness.getRow().metadata?.commissionReviewHistory ?? [];
  assert.equal(reviewHistory.length, 1);
  assert.equal(reviewHistory[0].approvalMode, 'RECEIPT_VERIFIED');
});

test('receipt approve retry does not increment activity or outbox counts', async () => {
  const harness = createRowLockHarness({
    status: 'SETTLEMENT_PENDING',
    commission_receipt_file_id: 11,
    receipt_mime_type: 'image/png',
    commission_status: COMMISSION_STATUS.DUE,
  });

  await harness.service.approve(BOOKING_NUMBER, ADMIN_A);
  const afterFirst = {
    activities: harness.counts.activityLogs.length,
    outbox: harness.counts.outboxEvents.length,
    transitions: harness.counts.transitions,
  };

  await harness.service.approve(BOOKING_NUMBER, ADMIN_B);

  assert.equal(harness.counts.activityLogs.length, afterFirst.activities);
  assert.equal(harness.counts.outboxEvents.length, afterFirst.outbox);
  assert.equal(harness.counts.transitions, afterFirst.transitions);
});

test('manual approve retry does not increment activity or outbox counts', async () => {
  const harness = createRowLockHarness({
    status: 'SETTLEMENT_PENDING',
    commission_receipt_file_id: null,
    commission_status: COMMISSION_STATUS.DUE,
    commission_amount: 200,
  });

  await harness.service.manualApproveWithoutReceipt(BOOKING_NUMBER, 'Confirmed', ADMIN_A);
  const afterFirst = {
    activities: harness.counts.activityLogs.length,
    outbox: harness.counts.outboxEvents.length,
    transitions: harness.counts.transitions,
  };

  await harness.service.manualApproveWithoutReceipt(BOOKING_NUMBER, 'Retry note', ADMIN_B);

  assert.equal(harness.counts.activityLogs.length, afterFirst.activities);
  assert.equal(harness.counts.outboxEvents.length, afterFirst.outbox);
  assert.equal(harness.counts.transitions, afterFirst.transitions);
});

test('receipt approve wins race against manual approve when receipt exists', async () => {
  const harness = createRowLockHarness({
    status: 'SETTLEMENT_PENDING',
    commission_receipt_file_id: 11,
    receipt_mime_type: 'image/png',
    commission_status: COMMISSION_STATUS.DUE,
  });

  const results = await Promise.allSettled([
    harness.service.approve(BOOKING_NUMBER, ADMIN_A),
    harness.service.manualApproveWithoutReceipt(BOOKING_NUMBER, 'Manual attempt', ADMIN_B),
  ]);

  const fulfilled = results.filter((row) => row.status === 'fulfilled');
  const rejected = results.filter((row) => row.status === 'rejected');
  assert.equal(fulfilled.length, 1);
  assert.equal(rejected.length, 1);
  assert.ok([
    ERROR_CODES.SETTLEMENT_MANUAL_APPROVAL_NOT_ALLOWED,
    ERROR_CODES.SETTLEMENT_ALREADY_APPROVED,
  ].includes(rejected[0].reason.errorCode));
  assert.equal(harness.getRow().metadata?.commissionApprovalMode, 'RECEIPT_VERIFIED');
  assert.equal(
    harness.counts.activityLogs.filter((log) => log.activityType === 'COMMISSION_APPROVED').length,
    1,
  );
  assert.equal(
    harness.counts.activityLogs.filter(
      (log) => log.activityType === 'MANUAL_SETTLEMENT_APPROVED_WITHOUT_RECEIPT',
    ).length,
    0,
  );
});

test('manual approve then upload rejects with RECEIPT_ALREADY_APPROVED', async () => {
  const harness = createRowLockHarness({
    status: 'SETTLEMENT_PENDING',
    commission_receipt_file_id: null,
    commission_status: COMMISSION_STATUS.DUE,
    commission_amount: 200,
  });

  await harness.service.manualApproveWithoutReceipt(BOOKING_NUMBER, 'Manual first', ADMIN_A);

  const tmp = path.join(uploadDir, 'phase3-manual-first.pdf');
  fs.writeFileSync(tmp, '%PDF-1.4');
  await assert.rejects(
    () => harness.service.uploadReceipt(44, BOOKING_NUMBER, {
      path: tmp,
      mimetype: 'application/pdf',
      size: 8,
      originalname: 'slip.pdf',
    }),
    (err) => err.errorCode === ERROR_CODES.RECEIPT_ALREADY_APPROVED,
  );
  if (fs.existsSync(tmp)) fs.unlinkSync(tmp);
  const staged = path.join(uploadDir, 'settlements', BOOKING_NUMBER);
  if (fs.existsSync(staged)) fs.rmSync(staged, { recursive: true, force: true });
});

test('upload then manual approve rejects with SETTLEMENT_MANUAL_APPROVAL_NOT_ALLOWED', async () => {
  const harness = createRowLockHarness({
    status: 'SETTLEMENT_PENDING',
    commission_receipt_file_id: null,
    commission_status: COMMISSION_STATUS.DUE,
    commission_amount: 200,
  });

  const tmp = path.join(uploadDir, 'phase3-upload-first.pdf');
  fs.writeFileSync(tmp, '%PDF-1.4');
  await harness.service.uploadReceipt(44, BOOKING_NUMBER, {
    path: tmp,
    mimetype: 'application/pdf',
    size: 8,
    originalname: 'slip.pdf',
  });
  if (fs.existsSync(tmp)) fs.unlinkSync(tmp);

  await assert.rejects(
    () => harness.service.manualApproveWithoutReceipt(BOOKING_NUMBER, 'Too late', ADMIN_A),
    (err) => err.errorCode === ERROR_CODES.SETTLEMENT_MANUAL_APPROVAL_NOT_ALLOWED,
  );
  const staged = path.join(uploadDir, 'settlements', BOOKING_NUMBER);
  if (fs.existsSync(staged)) fs.rmSync(staged, { recursive: true, force: true });
});

test('concurrent upload vs manual approve serializes without PAID manual plus active receipt', async () => {
  const harness = createRowLockHarness({
    status: 'SETTLEMENT_PENDING',
    commission_receipt_file_id: null,
    commission_status: COMMISSION_STATUS.DUE,
    commission_amount: 200,
  });

  const tmp = path.join(uploadDir, 'phase3-race.pdf');
  fs.writeFileSync(tmp, '%PDF-1.4');

  const results = await Promise.allSettled([
    harness.service.manualApproveWithoutReceipt(BOOKING_NUMBER, 'Manual race', ADMIN_A),
    harness.service.uploadReceipt(44, BOOKING_NUMBER, {
      path: tmp,
      mimetype: 'application/pdf',
      size: 8,
      originalname: 'slip.pdf',
    }),
  ]);

  if (fs.existsSync(tmp)) fs.unlinkSync(tmp);
  const staged = path.join(uploadDir, 'settlements', BOOKING_NUMBER);
  if (fs.existsSync(staged)) fs.rmSync(staged, { recursive: true, force: true });

  const fulfilled = results.filter((row) => row.status === 'fulfilled');
  const rejected = results.filter((row) => row.status === 'rejected');
  assert.equal(fulfilled.length, 1);
  assert.equal(rejected.length, 1);

  const row = harness.getRow();
  if (row.commission_status === COMMISSION_STATUS.PAID) {
    assert.equal(row.metadata?.commissionApprovalMode, 'MANUAL_WITHOUT_RECEIPT');
    assert.equal(row.commission_receipt_file_id, null);
  } else {
    assert.ok(row.commission_receipt_file_id != null);
    assert.notEqual(row.commission_status, COMMISSION_STATUS.PAID);
  }
});

test('approve post-commit dispatch failure does not rollback committed transaction', async () => {
  let rolledBack = false;
  const bookingRepo = {
    async findSettlementByBookingNumberForUpdate() {
      return settlementRow({
        status: 'SETTLEMENT_PENDING',
        commission_receipt_file_id: 11,
        receipt_mime_type: 'image/png',
      });
    },
    async findSettlementByBookingNumber() {
      return settlementRow({
        status: 'COMPLETED',
        commission_status: COMMISSION_STATUS.PAID,
        commission_receipt_file_id: 11,
        receipt_mime_type: 'image/png',
      });
    },
    async updateCommissionFields() {},
    async insertActivityLog() {},
    async findSettlementNotificationDriver() {
      return { driver_id: 5, driver_user_id: 44 };
    },
  };
  const conn = {
    async beginTransaction() {},
    async commit() {},
    async rollback() { rolledBack = true; },
    release() {},
  };
  const service = new CommissionSettlementService(
    { async getConnection() { return conn; } },
    bookingRepo,
    {},
    {},
    {},
    { async insertNotificationEvent() { return 55; } },
    {
      async dispatchOutboxIds() {
        throw new Error('dispatch failed');
      },
    },
    {
      async transitionInTransaction() {
        return { outboxId: 88, domainEvent: null, eventPayload: null };
      },
      async dispatchOutboxAfterCommit() {},
      emitDomainEvent() {},
    },
  );

  await assert.rejects(
    () => service.approve(BOOKING_NUMBER, ADMIN_A),
    /dispatch failed/,
  );
  assert.equal(rolledBack, false);
});

[
  ['DUE', COMMISSION_STATUS.DUE],
  ['OVERDUE', COMMISSION_STATUS.OVERDUE],
  ['PAID', COMMISSION_STATUS.PAID],
  ['WAIVED', COMMISSION_STATUS.WAIVED],
].forEach(([label, status]) => {
  test(`activation skips COMPLETED + ${label} + null amount`, async () => {
    const harness = createActivationHarness({
      id: 7,
      booking_number: BOOKING_NUMBER,
      status: 'COMPLETED',
      total_amount: 1200,
      currency: 'THB',
      commission_status: status,
      commission_amount: null,
      completed_at: '2026-07-01 12:00:00',
    });
    await harness.service.activateObligationForCompletedBooking(7);
    const counts = harness.getCounts();
    assert.equal(counts.updateCalls, 0, label);
    assert.equal(counts.activityLogs, 0, label);
    assert.equal(counts.outboxInserts, 0, label);
  });
});

test('activation still proceeds for COMPLETED + NOT_DUE_YET', async () => {
  const harness = createActivationHarness({
    id: 7,
    booking_number: BOOKING_NUMBER,
    status: 'COMPLETED',
    total_amount: 1200,
    currency: 'THB',
    commission_status: COMMISSION_STATUS.NOT_DUE_YET,
    commission_amount: null,
    completed_at: '2026-07-01 12:00:00',
    driver_id: 5,
  });
  await harness.service.activateObligationForCompletedBooking(7);
  const counts = harness.getCounts();
  assert.equal(counts.updateCalls, 1);
  assert.equal(counts.activityLogs, 1);
});

test('activation still proceeds for COMPLETED + PENDING_AFTER_COMPLETION', async () => {
  const harness = createActivationHarness({
    id: 7,
    booking_number: BOOKING_NUMBER,
    status: 'COMPLETED',
    total_amount: 1200,
    currency: 'THB',
    commission_status: COMMISSION_STATUS.PENDING_AFTER_COMPLETION,
    commission_amount: null,
    completed_at: '2026-07-01 12:00:00',
    driver_id: 5,
  });
  await harness.service.activateObligationForCompletedBooking(7);
  const counts = harness.getCounts();
  assert.equal(counts.updateCalls, 1);
  assert.equal(counts.activityLogs, 1);
});

test('receipt approve emits settlement.approved outbox from assignment when bookings.driver_id is null', async () => {
  const harness = createRowLockHarness(
    settlementRow({
      driver_id: null,
      commission_receipt_file_id: 11,
      receipt_mime_type: 'application/pdf',
    }),
    { assignmentDriverId: 11, assignmentDriverUserId: 15 },
  );

  await harness.service.approve(BOOKING_NUMBER, ADMIN_A);

  assert.equal(
    harness.counts.outboxEvents.filter((event) => event.eventType === EVENTS.SETTLEMENT_APPROVED).length,
    1,
  );
  const outbox = harness.counts.outboxEvents[0];
  assert.equal(outbox.payload.driverId, 11);
  assert.equal(outbox.payload.driverUserId, 15);
});

test('receipt approve retry keeps settlement.approved outbox count at 1 when driver_id is null', async () => {
  const harness = createRowLockHarness(
    settlementRow({
      driver_id: null,
      commission_receipt_file_id: 11,
      receipt_mime_type: 'application/pdf',
    }),
    { assignmentDriverId: 11, assignmentDriverUserId: 15 },
  );

  await harness.service.approve(BOOKING_NUMBER, ADMIN_A);
  await harness.service.approve(BOOKING_NUMBER, ADMIN_B);

  assert.equal(
    harness.counts.outboxEvents.filter((event) => event.eventType === EVENTS.SETTLEMENT_APPROVED).length,
    1,
  );
});

test('manual approve emits settlement.approved outbox from assignment when bookings.driver_id is null', async () => {
  const harness = createRowLockHarness(
    settlementRow({
      driver_id: null,
      commission_receipt_file_id: null,
      commission_amount: 200,
    }),
    { assignmentDriverId: 11, assignmentDriverUserId: 15 },
  );

  await harness.service.manualApproveWithoutReceipt(
    BOOKING_NUMBER,
    'AUTOMATED_REGRESSION_TEST',
    ADMIN_A,
  );

  assert.equal(
    harness.counts.outboxEvents.filter((event) => event.eventType === EVENTS.SETTLEMENT_APPROVED).length,
    1,
  );
  const outbox = harness.counts.outboxEvents[0];
  assert.equal(outbox.payload.driverId, 11);
  assert.equal(outbox.payload.driverUserId, 15);
  assert.equal(outbox.payload.approvalMode, 'MANUAL_WITHOUT_RECEIPT');
});

test('manual approve retry keeps settlement.approved outbox count at 1 when driver_id is null', async () => {
  const harness = createRowLockHarness(
    settlementRow({
      driver_id: null,
      commission_receipt_file_id: null,
      commission_amount: 200,
    }),
    { assignmentDriverId: 11, assignmentDriverUserId: 15 },
  );

  await harness.service.manualApproveWithoutReceipt(
    BOOKING_NUMBER,
    'AUTOMATED_REGRESSION_TEST',
    ADMIN_A,
  );
  await harness.service.manualApproveWithoutReceipt(
    BOOKING_NUMBER,
    'AUTOMATED_REGRESSION_TEST',
    ADMIN_B,
  );

  assert.equal(
    harness.counts.outboxEvents.filter((event) => event.eventType === EVENTS.SETTLEMENT_APPROVED).length,
    1,
  );
});

test('null bookings.driver_id with missing assignment driver suppresses outbox', async () => {
  const harness = createRowLockHarness(
    settlementRow({
      driver_id: null,
      commission_receipt_file_id: 11,
      receipt_mime_type: 'application/pdf',
    }),
    { assignmentDriverId: null, assignmentDriverUserId: null },
  );

  await harness.service.approve(BOOKING_NUMBER, ADMIN_A);

  assert.equal(harness.counts.outboxEvents.length, 0);
});
