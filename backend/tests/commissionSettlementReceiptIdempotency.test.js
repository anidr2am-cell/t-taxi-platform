process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';

const fs = require('fs');
const path = require('path');
const { test } = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');

const ERROR_CODES = require('../src/constants/errorCodes');
const HTTP_STATUS = require('../src/constants/httpStatus');
const COMMISSION_STATUS = require('../src/constants/commissionStatus');
const ROLES = require('../src/constants/roles');
const CommissionSettlementService = require('../src/services/commissionSettlement.service');
const SettlementReceiptIdempotencyService = require('../src/services/settlementReceiptIdempotency.service');
const { uploadDir } = require('../src/config/multer');
const {
  computeSettlementReceiptFingerprint,
} = require('../src/utils/settlementReceiptIdempotency.util');

function settlementRow(overrides = {}) {
  return {
    id: 7,
    booking_number: 'TX202607010001',
    status: 'SETTLEMENT_PENDING',
    completed_at: '2026-07-01 12:00:00',
    total_amount: 1200,
    currency: 'THB',
    commission_status: COMMISSION_STATUS.DUE,
    commission_amount: 120,
    commission_due_at: '2026-07-10 12:00:00',
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

function createTempReceipt(content = '%PDF-1.4') {
  const tmp = path.join(uploadDir, `receipt-test-${crypto.randomUUID()}.pdf`);
  fs.writeFileSync(tmp, content);
  return {
    path: tmp,
    mimetype: 'application/pdf',
    size: Buffer.byteLength(content),
    originalname: 'receipt.pdf',
  };
}

function cleanupBookingArtifacts(bookingNumber) {
  const staged = path.join(uploadDir, 'settlements', bookingNumber);
  if (fs.existsSync(staged)) {
    fs.rmSync(staged, { recursive: true, force: true });
  }
}

class InMemoryReceiptIdempotencyRepository {
  constructor() {
    this.rows = new Map();
    this.lockChain = Promise.resolve();
  }

  key(scope) {
    return `${scope.bookingId}:${scope.driverUserId}:${scope.idempotencyKey}`;
  }

  async withLock(fn) {
    const previous = this.lockChain;
    let release;
    this.lockChain = new Promise((resolve) => {
      release = resolve;
    });
    await previous;
    try {
      return await fn();
    } finally {
      release();
    }
  }

  async findByScopeForUpdate(_conn, scope) {
    return this.withLock(async () => this.rows.get(this.key(scope)) ?? null);
  }

  async insertPending(_conn, row) {
    return this.withLock(async () => {
      const key = this.key(row);
      if (this.rows.has(key)) {
        const err = new Error('Duplicate entry');
        err.code = 'ER_DUP_ENTRY';
        throw err;
      }
      this.rows.set(key, {
        booking_id: row.bookingId,
        driver_user_id: row.driverUserId,
        idempotency_key: row.idempotencyKey,
        request_fingerprint: row.requestFingerprint,
        status: 'PENDING',
        receipt_file_id: null,
        response_status: 200,
        response_payload: null,
      });
      return 1;
    });
  }

  async markCompleted(_conn, row) {
    return this.withLock(async () => {
      const existing = this.rows.get(this.key(row));
      if (!existing || existing.status !== 'PENDING') return;
      existing.status = 'COMPLETED';
      existing.receipt_file_id = row.receiptFileId;
      existing.response_status = row.responseStatus;
      existing.response_payload = JSON.stringify(row.responsePayload);
    });
  }

  async deletePending(_conn, scope) {
    return this.withLock(async () => {
      const existing = this.rows.get(this.key(scope));
      if (existing?.status === 'PENDING') {
        this.rows.delete(this.key(scope));
      }
    });
  }

  async deleteExpiredBatch() {
    return 0;
  }
}

function createUploadHarness(overrides = {}) {
  const calls = {
    fileInserts: [],
    activityLogs: [],
    outboxEvents: [],
    softDeletes: [],
  };
  let nextFileId = overrides.nextFileId ?? 501;
  let bookingState = settlementRow(overrides.booking ?? {});

  const bookingRepo = {
    async findSettlementByBookingNumberForUpdate() {
      return { ...bookingState };
    },
    async driverOwnsSettlementBooking(driverId, bookingNumber) {
      if (overrides.driverOwns === false) return false;
      return Number(driverId) === Number(bookingState.driver_id)
        && bookingNumber === bookingState.booking_number;
    },
    async updateCommissionFields(_conn, _id, fields) {
      bookingState = {
        ...bookingState,
        commission_receipt_file_id: fields.commissionReceiptFileId,
        metadata: fields.metadata,
      };
    },
    async insertActivityLog(_conn, _id, entry) {
      calls.activityLogs.push(entry);
    },
    async findSettlementByBookingNumber() {
      return {
        ...bookingState,
        receipt_mime_type: bookingState.commission_receipt_file_id ? 'application/pdf' : null,
        receipt_original_filename: bookingState.commission_receipt_file_id ? 'receipt.pdf' : null,
        receipt_file_size: bookingState.commission_receipt_file_id ? 8 : null,
      };
    },
  };

  const fileRepo = {
    async insert(_conn, row) {
      if (overrides.insertThrows) {
        throw overrides.insertThrows;
      }
      const id = nextFileId;
      nextFileId += 1;
      calls.fileInserts.push({ id, ...row });
      return id;
    },
    async softDelete(_conn, fileId) {
      calls.softDeletes.push(fileId);
    },
  };

  const conn = {
    async beginTransaction() {},
    async commit() {},
    async rollback() {},
    release() {},
  };
  const pool = { async getConnection() { return conn; } };

  const idempotencyRepo = overrides.idempotencyRepo ?? new InMemoryReceiptIdempotencyRepository();
  const idempotencyService = new SettlementReceiptIdempotencyService(idempotencyRepo);

  const service = new CommissionSettlementService(
    pool,
    bookingRepo,
    {
      async findByUserId(userId) {
        if (overrides.driverId != null) return { id: overrides.driverId };
        return { id: userId === 99 ? 8 : 5 };
      },
    },
    fileRepo,
    {},
    overrides.outboxRepository ?? {
      async insertNotificationEvent(_conn, event) {
        calls.outboxEvents.push(event);
        return 9001;
      },
    },
    overrides.outboxProcessor ?? { async dispatchOutboxIds() {} },
    null,
    idempotencyService,
  );

  return {
    service,
    calls,
    getBookingState: () => bookingState,
    idempotencyRepo,
  };
}

test('first receipt upload persists file, activity, and outbox once', async () => {
  const { service, calls } = createUploadHarness();
  const file = createTempReceipt('%PDF-first');
  try {
    const result = await service.uploadReceipt(44, 'TX202607010001', file, {
      idempotencyKey: 'receipt-key-001',
    });
    assert.equal(result.idempotent, false);
    assert.equal(calls.fileInserts.length, 1);
    assert.equal(calls.activityLogs.length, 1);
    assert.equal(calls.outboxEvents.length, 1);
    assert.equal(result.receiptFileId, 501);
  } finally {
    if (fs.existsSync(file.path)) fs.unlinkSync(file.path);
    cleanupBookingArtifacts('TX202607010001');
  }
});

test('same key and same file retry replays without duplicate side effects', async () => {
  const { service, calls } = createUploadHarness();
  const file = createTempReceipt('%PDF-retry');
  const options = { idempotencyKey: 'receipt-key-retry' };
  try {
    const first = await service.uploadReceipt(44, 'TX202607010001', file, options);
    const retryFile = createTempReceipt('%PDF-retry');
    const second = await service.uploadReceipt(44, 'TX202607010001', retryFile, options);
    assert.equal(first.receiptFileId, 501);
    assert.equal(second.receiptFileId, 501);
    assert.equal(second.idempotent, true);
    assert.equal(calls.fileInserts.length, 1);
    assert.equal(calls.activityLogs.length, 1);
    assert.equal(calls.outboxEvents.length, 1);
    if (fs.existsSync(retryFile.path)) fs.unlinkSync(retryFile.path);
  } finally {
    if (fs.existsSync(file.path)) fs.unlinkSync(file.path);
    cleanupBookingArtifacts('TX202607010001');
  }
});

test('same key with different file content returns conflict and keeps original receipt', async () => {
  const { service, calls } = createUploadHarness();
  const file = createTempReceipt('%PDF-original');
  try {
    await service.uploadReceipt(44, 'TX202607010001', file, {
      idempotencyKey: 'receipt-key-diff',
    });
    const different = createTempReceipt('%PDF-different');
    await assert.rejects(
      () => service.uploadReceipt(44, 'TX202607010001', different, {
        idempotencyKey: 'receipt-key-diff',
      }),
      (err) => err.statusCode === HTTP_STATUS.CONFLICT
        && err.errorCode === ERROR_CODES.IDEMPOTENCY_KEY_REUSED,
    );
    assert.equal(calls.fileInserts.length, 1);
    assert.equal(calls.fileInserts[0].id, 501);
    if (fs.existsSync(different.path)) fs.unlinkSync(different.path);
  } finally {
    if (fs.existsSync(file.path)) fs.unlinkSync(file.path);
    cleanupBookingArtifacts('TX202607010001');
  }
});

test('concurrent same-key uploads produce one stored receipt', async () => {
  const idempotencyRepo = new InMemoryReceiptIdempotencyRepository();
  const { service, calls } = createUploadHarness({ idempotencyRepo });
  const fileA = createTempReceipt('%PDF-concurrent');
  const fileB = createTempReceipt('%PDF-concurrent');
  const options = { idempotencyKey: 'receipt-key-concurrent' };
  try {
    const results = await Promise.allSettled([
      service.uploadReceipt(44, 'TX202607010001', fileA, options),
      service.uploadReceipt(44, 'TX202607010001', fileB, options),
    ]);
    const fulfilled = results.filter((entry) => entry.status === 'fulfilled');
    const rejected = results.filter((entry) => entry.status === 'rejected');
    assert.equal(fulfilled.length + rejected.length, 2);
    assert.equal(calls.fileInserts.length, 1);
    assert.equal(calls.activityLogs.length, 1);
    assert.equal(calls.outboxEvents.length, 1);
    if (rejected.length === 1) {
      assert.ok([
        ERROR_CODES.IDEMPOTENCY_REQUEST_IN_PROGRESS,
        ERROR_CODES.IDEMPOTENCY_KEY_REUSED,
      ].includes(rejected[0].reason.errorCode));
    }
    if (fulfilled.length === 2) {
      assert.equal(fulfilled[0].value.receiptFileId, fulfilled[1].value.receiptFileId);
    }
  } finally {
    if (fs.existsSync(fileA.path)) fs.unlinkSync(fileA.path);
    if (fs.existsSync(fileB.path)) fs.unlinkSync(fileB.path);
    cleanupBookingArtifacts('TX202607010001');
  }
});

test('new key replaces previous receipt and soft-deletes old file once', async () => {
  const { service, calls } = createUploadHarness({
    booking: { commission_receipt_file_id: 400 },
  });
  const file = createTempReceipt('%PDF-replace');
  try {
    const result = await service.uploadReceipt(44, 'TX202607010001', file, {
      idempotencyKey: 'receipt-key-new',
    });
    assert.equal(result.receiptFileId, 501);
    assert.deepEqual(calls.softDeletes, [400]);
    assert.equal(calls.fileInserts.length, 1);
  } finally {
    if (fs.existsSync(file.path)) fs.unlinkSync(file.path);
    cleanupBookingArtifacts('TX202607010001');
  }
});

test('DB failure after staged file write cleans staged file and releases pending idempotency', async () => {
  const { service, idempotencyRepo } = createUploadHarness({
    insertThrows: new Error('db insert failed'),
  });
  const file = createTempReceipt('%PDF-db-fail');
  try {
    await assert.rejects(
      () => service.uploadReceipt(44, 'TX202607010001', file, {
        idempotencyKey: 'receipt-key-db-fail',
      }),
      (err) => err.message === 'db insert failed',
    );
    const pending = await idempotencyRepo.findByScopeForUpdate(null, {
      bookingId: 7,
      driverUserId: 44,
      idempotencyKey: 'receipt-key-db-fail',
    });
    assert.equal(pending, null);
    const stagedDir = path.join(uploadDir, 'settlements', 'TX202607010001');
    if (fs.existsSync(stagedDir)) {
      assert.equal(fs.readdirSync(stagedDir).length, 0);
    }
  } finally {
    if (fs.existsSync(file.path)) fs.unlinkSync(file.path);
    cleanupBookingArtifacts('TX202607010001');
  }
});

test('file write failure leaves DB unchanged', async () => {
  const originalCopy = fs.copyFileSync;
  const { service, calls } = createUploadHarness();
  const file = createTempReceipt('%PDF-write-fail');
  fs.copyFileSync = () => {
    throw new Error('disk full');
  };
  try {
    await assert.rejects(
      () => service.uploadReceipt(44, 'TX202607010001', file, {
        idempotencyKey: 'receipt-key-write-fail',
      }),
      (err) => err.message === 'disk full',
    );
    assert.equal(calls.fileInserts.length, 0);
    assert.equal(calls.activityLogs.length, 0);
    assert.equal(calls.outboxEvents.length, 0);
  } finally {
    fs.copyFileSync = originalCopy;
    if (fs.existsSync(file.path)) fs.unlinkSync(file.path);
    cleanupBookingArtifacts('TX202607010001');
  }
});

test('other driver cannot replay another driver scoped idempotency key', async () => {
  const sharedRepo = new InMemoryReceiptIdempotencyRepository();
  const { service } = createUploadHarness({ idempotencyRepo: sharedRepo });
  const file = createTempReceipt('%PDF-scope');
  try {
    await service.uploadReceipt(44, 'TX202607010001', file, {
      idempotencyKey: 'shared-key',
    });
    const otherDriverHarness = createUploadHarness({
      idempotencyRepo: sharedRepo,
      driverId: 8,
    });
    const retryFile = createTempReceipt('%PDF-scope');
    await assert.rejects(
      () => otherDriverHarness.service.uploadReceipt(99, 'TX202607010001', retryFile, {
        idempotencyKey: 'shared-key',
      }),
      (err) => err.statusCode === HTTP_STATUS.NOT_FOUND,
    );
    assert.equal(otherDriverHarness.calls.fileInserts.length, 0);
    if (fs.existsSync(retryFile.path)) fs.unlinkSync(retryFile.path);
  } finally {
    if (fs.existsSync(file.path)) fs.unlinkSync(file.path);
    cleanupBookingArtifacts('TX202607010001');
  }
});

test('settlement receipt fingerprint includes booking, driver, and content hash', () => {
  const fingerprint = computeSettlementReceiptFingerprint({
    bookingId: 7,
    driverUserId: 44,
    contentHash: 'abc123',
  });
  assert.match(fingerprint, /^[a-f0-9]{64}$/);
  const differentDriver = computeSettlementReceiptFingerprint({
    bookingId: 7,
    driverUserId: 45,
    contentHash: 'abc123',
  });
  assert.notEqual(fingerprint, differentDriver);
});
