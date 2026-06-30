process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const { test, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const jwt = require('jsonwebtoken');
const request = require('supertest');

const app = require('../src/app');
const container = require('../src/helpers/container');
const AdminQrReissueService = require('../src/services/adminQrReissue.service');
const DriverQrService = require('../src/services/driverQr.service');
const { hashToken } = require('../src/utils/tokenHash.util');
const ERROR_CODES = require('../src/constants/errorCodes');
const BOOKING_STATUS = require('../src/constants/reservationStatus');

const originalAllow = process.env.ALLOW_DEV_QR_REISSUE;

function sign(role = 'ADMIN', id = 1) {
  return jwt.sign(
    { sub: id, email: `${role.toLowerCase()}@example.com`, role, type: 'access' },
    process.env.JWT_ACCESS_SECRET,
    { expiresIn: '1h' },
  );
}

function bookingRow(overrides = {}) {
  return {
    id: 10,
    booking_number: 'TX202607010001',
    status: BOOKING_STATUS.DRIVER_ARRIVED,
    scheduled_pickup_at: '2026-07-01 09:30:00',
    boarding_qr_token_hash: hashToken('old-boarding'),
    boarding_qr_used_at: null,
    dropoff_qr_token_hash: null,
    dropoff_qr_used_at: null,
    ...overrides,
  };
}

beforeEach(() => {
  process.env.ALLOW_DEV_QR_REISSUE = 'true';
});

afterEach(() => {
  if (originalAllow === undefined) {
    delete process.env.ALLOW_DEV_QR_REISSUE;
  } else {
    process.env.ALLOW_DEV_QR_REISSUE = originalAllow;
  }
});

test('dev QR reissue disabled by default in production', async () => {
  const service = new AdminQrReissueService({}, {}, {
    allowDevQrReissue: true,
    nodeEnv: 'production',
  });
  assert.equal(service.isEnabled(), false);

  await assert.rejects(
    () => service.reissueQr('TX202607010001', 'BOARDING', { id: 1, role: 'ADMIN' }),
    (err) => err.errorCode === ERROR_CODES.FORBIDDEN,
  );
});

test('dev QR reissue disabled when flag is false', async () => {
  const service = new AdminQrReissueService({}, {}, {
    allowDevQrReissue: false,
    nodeEnv: 'development',
  });
  assert.equal(service.isEnabled(), false);
  assert.match(service.disabledReason(), /ALLOW_DEV_QR_REISSUE/);
});

test('dev QR reissue enabled in development when feature resolver allows it', () => {
  const service = new AdminQrReissueService({}, {}, {
    allowDevQrReissue: true,
    nodeEnv: 'development',
  });
  assert.equal(service.isEnabled(), true);
});

test('boarding QR reissue stores new hash and returns token once', async () => {
  const calls = { setBoardingQr: [], activityLogs: [] };
  const row = bookingRow();
  const conn = {
    async beginTransaction() {},
    async commit() {},
    async rollback() {},
    release() {},
  };
  const pool = { async getConnection() { return conn; } };
  const bookingRepo = {
    async findByBookingNumberForUpdate() { return row; },
    async setBoardingQr(_conn, bookingId, tokenHash, expiresAt) {
      calls.setBoardingQr.push({ bookingId, tokenHash, expiresAt });
    },
    async insertActivityLog(_conn, bookingId, activity) {
      calls.activityLogs.push({ bookingId, activity });
    },
  };
  const service = new AdminQrReissueService(pool, bookingRepo, {
    allowDevQrReissue: true,
    nodeEnv: 'development',
  });

  const result = await service.reissueQr(
    'TX202607010001',
    'BOARDING',
    { id: 1, role: 'ADMIN' },
  );

  assert.equal(result.qrType, 'BOARDING');
  assert.ok(result.boardingQrToken);
  assert.equal(calls.setBoardingQr.length, 1);
  assert.equal(calls.setBoardingQr[0].tokenHash, hashToken(result.boardingQrToken));
  assert.notEqual(calls.setBoardingQr[0].tokenHash, hashToken('old-boarding'));
  assert.equal(calls.activityLogs[0].activity.activityType, 'QR_TOKEN_REISSUED');
  assert.equal(calls.activityLogs[0].activity.payload.qrType, 'BOARDING');
  assert.ok(!JSON.stringify(calls.activityLogs).includes(result.boardingQrToken));
});

test('dropoff QR reissue requires PICKED_UP status', async () => {
  const conn = {
    async beginTransaction() {},
    async commit() {},
    async rollback() {},
    release() {},
  };
  const pool = { async getConnection() { return conn; } };
  const service = new AdminQrReissueService(pool, {
    async findByBookingNumberForUpdate() {
      return bookingRow({ status: BOOKING_STATUS.DRIVER_ARRIVED });
    },
  }, {
    allowDevQrReissue: true,
    nodeEnv: 'development',
  });

  await assert.rejects(
    () => service.reissueQr('TX202607010001', 'DROPOFF', { id: 1, role: 'ADMIN' }),
    (err) => err.errorCode === ERROR_CODES.INVALID_STATUS_TRANSITION,
  );
});

test('reissued boarding token passes driver QR verification', async () => {
  let storedHash = hashToken('old-boarding');
  const row = {
    id: 10,
    booking_number: 'TX202607010001',
    status: BOOKING_STATUS.DRIVER_ARRIVED,
    boarding_qr_token_hash: storedHash,
    boarding_qr_expires_at: '2099-01-01 00:00:00',
    boarding_qr_used_at: null,
    dropoff_qr_token_hash: null,
  };
  const conn = {
    async beginTransaction() {},
    async commit() {},
    async rollback() {},
    release() {},
  };
  const pool = { async getConnection() { return conn; } };

  const reissueService = new AdminQrReissueService(pool, {
    async findByBookingNumberForUpdate() { return bookingRow(); },
    async setBoardingQr(_conn, _bookingId, tokenHash) {
      storedHash = tokenHash;
      row.boarding_qr_token_hash = tokenHash;
    },
    async insertActivityLog() {},
  }, {
    allowDevQrReissue: true,
    nodeEnv: 'development',
  });

  const reissued = await reissueService.reissueQr(
    'TX202607010001',
    'BOARDING',
    { id: 1, role: 'ADMIN' },
  );

  const driverQr = new DriverQrService(pool, {
    async findActiveDriverBookingByNumberForUpdate() {
      return { ...row, boarding_qr_token_hash: storedHash };
    },
    async findQrTokenBooking() { return null; },
    async markBoardingQrUsed() { return true; },
  }, {
    async transitionInTransaction() {
      return { outboxId: null, domainEvent: null, eventPayload: null, result: { idempotent: false } };
    },
    async dispatchOutboxAfterCommit() {},
    emitDomainEvent() {},
  }, {
    validateBookingNumber: (value) => value,
    async getDetail() {
      return { bookingNumber: 'TX202607010001', status: BOOKING_STATUS.PICKED_UP };
    },
  });

  await assert.rejects(
    () => driverQr.scanBoarding(9, 'TX202607010001', 'old-boarding'),
    (err) => err.errorCode === ERROR_CODES.INVALID_QR_TOKEN,
  );

  const detail = await driverQr.scanBoarding(9, 'TX202607010001', reissued.boardingQrToken);
  assert.equal(detail.status, BOOKING_STATUS.PICKED_UP);
});

test('ADMIN can reissue QR when dev flag enabled', async () => {
  container.register('adminQrReissueService', () => ({
    async reissueQr(_bookingNumber, type) {
      return {
        bookingNumber: 'TX202607010001',
        qrType: type,
        boardingQrToken: 'new-boarding-token',
        expiresAt: '2099-01-01 00:00:00',
      };
    },
  }));

  const res = await request(app)
    .post('/api/v1/admin/bookings/TX202607010001/qr/reissue')
    .set('Authorization', `Bearer ${sign('ADMIN')}`)
    .send({ type: 'BOARDING' });

  assert.equal(res.status, 200);
  assert.equal(res.body.data.boardingQrToken, 'new-boarding-token');
});

test('DRIVER cannot reissue QR', async () => {
  container.register('adminQrReissueService', () => ({
    async reissueQr() {
      return { boardingQrToken: 'secret' };
    },
  }));

  const res = await request(app)
    .post('/api/v1/admin/bookings/TX202607010001/qr/reissue')
    .set('Authorization', `Bearer ${sign('DRIVER', 9)}`)
    .send({ type: 'BOARDING' });

  assert.equal(res.status, 403);
});

test('QR reissue blocked when service disabled', async () => {
  container.register('adminQrReissueService', () => new AdminQrReissueService({}, {}, {
    allowDevQrReissue: false,
    nodeEnv: 'development',
  }));

  const res = await request(app)
    .post('/api/v1/admin/bookings/TX202607010001/qr/reissue')
    .set('Authorization', `Bearer ${sign('ADMIN')}`)
    .send({ type: 'BOARDING' });

  assert.equal(res.status, 403);
  assert.equal(res.body.error_code, ERROR_CODES.FORBIDDEN);
});
