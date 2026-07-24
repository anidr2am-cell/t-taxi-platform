process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const jwt = require('jsonwebtoken');
const request = require('supertest');
const DriverStatusService = require('../src/services/driverStatus.service');
const DriverCandidateScoringService = require('../src/services/driverCandidateScoring.service');
const ERROR_CODES = require('../src/constants/errorCodes');
const ROLES = require('../src/constants/roles');
const container = require('../src/helpers/container');
const app = require('../src/app');

function sign(role = ROLES.DRIVER, id = 44) {
  return jwt.sign(
    { sub: id, email: `${role.toLowerCase()}@example.com`, role, type: 'access' },
    process.env.JWT_ACCESS_SECRET,
    { expiresIn: '1h' },
  );
}

function makePool() {
  return {
    async getConnection() {
      return {
        async beginTransaction() {},
        async commit() {},
        async rollback() {},
        release() {},
      };
    },
  };
}

function driver(overrides = {}) {
  return {
    id: 7,
    user_id: 44,
    name: 'Driver',
    status: 'OFFLINE',
    is_online: 0,
    is_active: 1,
    user_is_active: 1,
    active_job_count: 0,
    last_seen_at: null,
    ...overrides,
  };
}

function makeService({ current = driver(), activeJob = false, blocked = false } = {}) {
  const updates = [];
  const repository = {
    async findByUserId(userId) {
      return { ...current, user_id: userId, active_job_count: activeJob ? 1 : 0 };
    },
    async findByUserIdForUpdate(_conn, userId) {
      return { ...current, user_id: userId };
    },
    async hasActiveJob() {
      return activeJob;
    },
    async updateOnlineState(_conn, driverId, next) {
      updates.push({ driverId, ...next });
      current = {
        ...current,
        is_online: next.isOnline ? 1 : 0,
        status: next.status,
        last_seen_at: '2026-06-30 09:00:00',
      };
    },
  };
  const settlement = {
    async driverHasBlockingSettlement() {
      return blocked;
    },
  };
  const service = new DriverStatusService(makePool(), repository, settlement);
  service.updates = updates;
  return service;
}

test('DRIVER can go online and last_seen_at is updated', async () => {
  const service = makeService();
  const result = await service.goOnline(44);
  assert.equal(result.online, true);
  assert.equal(result.status, 'AVAILABLE');
  assert.equal(result.lastSeenAt, '2026-06-30 09:00:00');
  assert.deepEqual(service.updates[0], {
    driverId: 7,
    isOnline: true,
    status: 'AVAILABLE',
  });
});

test('DRIVER can go offline when no active job exists', async () => {
  const service = makeService({ current: driver({ status: 'AVAILABLE', is_online: 1 }) });
  const result = await service.goOffline(44);
  assert.equal(result.online, false);
  assert.equal(result.status, 'OFFLINE');
});

test('inactive and suspended drivers cannot go online', async () => {
  await assert.rejects(
    () => makeService({ current: driver({ is_active: 0 }) }).goOnline(44),
    (err) => err.errorCode === ERROR_CODES.DRIVER_NOT_FOUND,
  );
  await assert.rejects(
    () => makeService({ current: driver({ status: 'SUSPENDED' }) }).goOnline(44),
    (err) => err.errorCode === ERROR_CODES.DRIVER_NOT_ELIGIBLE,
  );
});

test('settlement-blocked driver cannot go online', async () => {
  await assert.rejects(
    () => makeService({ blocked: true }).goOnline(44),
    (err) => err.errorCode === ERROR_CODES.DRIVER_NOT_ELIGIBLE,
  );
});

test('GET status exposes safe online payload', async () => {
  const service = makeService({
    current: driver({ status: 'AVAILABLE', is_online: 1, last_seen_at: '2026-06-30 09:00:00' }),
    activeJob: true,
  });
  const result = await service.getStatus(44);
  assert.deepEqual(result, {
    driverId: 7,
    active: true,
    online: true,
    status: 'AVAILABLE',
    hasActiveJob: true,
    lastSeenAt: '2026-06-30 09:00:00',
    callEligibility: {
      canReceiveCalls: true,
      reasonCode: 'READY',
    },
  });
  assert.equal('phone' in result, false);
  assert.equal('userId' in result, false);
});

test('GET status exposes ready call eligibility', async () => {
  const service = makeService({
    current: driver({ status: 'AVAILABLE', is_online: 1, active_vehicle_count: 1 }),
  });
  const result = await service.getStatus(44);

  assert.deepEqual(result.callEligibility, {
    canReceiveCalls: true,
    reasonCode: 'READY',
  });
});

test('GET status explains offline call eligibility', async () => {
  const service = makeService({
    current: driver({ status: 'OFFLINE', is_online: 0, active_vehicle_count: 1 }),
  });
  const result = await service.getStatus(44);

  assert.deepEqual(result.callEligibility, {
    canReceiveCalls: false,
    reasonCode: 'OFFLINE',
  });
});

test('GET status explains settlement and vehicle restrictions', async () => {
  const settlementBlocked = makeService({
    current: driver({ status: 'AVAILABLE', is_online: 1, active_vehicle_count: 1 }),
    blocked: true,
  });
  const settlement = await settlementBlocked.getStatus(44);
  assert.deepEqual(settlement.callEligibility, {
    canReceiveCalls: false,
    reasonCode: 'UNPAID_SETTLEMENT',
  });

  const noVehicle = makeService({
    current: driver({ status: 'AVAILABLE', is_online: 1, active_vehicle_count: 0 }),
  });
  const vehicle = await noVehicle.getStatus(44);
  assert.deepEqual(vehicle.callEligibility, {
    canReceiveCalls: false,
    reasonCode: 'VEHICLE_REVIEW_REQUIRED',
  });
});

test('GET status prioritizes account restrictions before other blockers', async () => {
  const service = makeService({
    current: driver({
      status: 'SUSPENDED',
      is_online: 1,
      active_vehicle_count: 0,
    }),
    activeJob: true,
    blocked: true,
  });
  const result = await service.getStatus(44);

  assert.deepEqual(result.callEligibility, {
    canReceiveCalls: false,
    reasonCode: 'ACCOUNT_RESTRICTED',
  });
});

test('GET status explains driver approval review states', async () => {
  const service = makeService({
    current: driver({ status: 'PENDING_APPROVAL', is_online: 1, active_vehicle_count: 1 }),
  });
  const result = await service.getStatus(44);

  assert.deepEqual(result.callEligibility, {
    canReceiveCalls: false,
    reasonCode: 'DRIVER_APPROVAL_PENDING',
  });
});

test('offline with active job is rejected', async () => {
  const service = makeService({
    current: driver({ status: 'AVAILABLE', is_online: 1 }),
    activeJob: true,
  });
  await assert.rejects(
    () => service.goOffline(44),
    (err) => err.statusCode === 409 && err.errorCode === ERROR_CODES.DRIVER_NOT_AVAILABLE,
  );
});

test('offline driver excluded and online driver eligible for auto assignment scoring', () => {
  const scoring = new DriverCandidateScoringService();
  const booking = { vehicle_type_id: 1 };
  const base = {
    id: 7,
    name: 'Driver',
    is_active: 1,
    user_is_active: 1,
    primary_vehicle_type_id: 1,
    primary_vehicle_id: 10,
    active_assignment_count: 0,
    location_updated_at: new Date().toISOString(),
  };
  const offline = scoring.buildCandidate({ ...base, status: 'OFFLINE', is_online: 0 }, booking);
  const online = scoring.buildCandidate({ ...base, status: 'AVAILABLE', is_online: 1 }, booking);
  assert.equal(offline.eligible, false);
  assert.ok(offline.exclusionReasons.includes('OFFLINE'));
  assert.equal(online.eligible, true);
});

test('driver status endpoints require DRIVER role', async () => {
  container.register('driverStatusService', () => ({
    async getStatus() {
      return { driverId: 7, active: true, online: false, status: 'OFFLINE', hasActiveJob: false, lastSeenAt: null };
    },
    async goOnline() {
      return { driverId: 7, active: true, online: true, status: 'AVAILABLE', hasActiveJob: false, lastSeenAt: 'now' };
    },
    async goOffline() {
      return { driverId: 7, active: true, online: false, status: 'OFFLINE', hasActiveJob: false, lastSeenAt: 'now' };
    },
  }));
  const ok = await request(app)
    .post('/api/v1/driver/online')
    .set('Authorization', `Bearer ${sign(ROLES.DRIVER, 44)}`);
  assert.equal(ok.status, 200);

  const admin = await request(app)
    .post('/api/v1/driver/online')
    .set('Authorization', `Bearer ${sign(ROLES.ADMIN, 1)}`);
  assert.equal(admin.status, 403);

  const anon = await request(app).get('/api/v1/driver/status');
  assert.equal(anon.status, 401);
});

test('logout succeeds even when best-effort offline fails', async () => {
  container.register('driverStatusService', () => ({
    async goOfflineBestEffort() {
      throw new Error('offline update failed');
    },
  }));
  const res = await request(app)
    .post('/api/v1/auth/logout')
    .set('Authorization', `Bearer ${sign(ROLES.DRIVER, 44)}`)
    .send({});
  assert.equal(res.status, 200);
});
