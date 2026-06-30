process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const jwt = require('jsonwebtoken');
const request = require('supertest');

const FlightSyncWorker = require('../src/workers/flightSync.worker');
const FlightSyncSchedulerService = require('../src/services/flightSyncScheduler.service');
const AppError = require('../src/utils/AppError');
const ERROR_CODES = require('../src/constants/errorCodes');
const FLIGHT_STATUS = require('../src/constants/flightStatus');
const container = require('../src/helpers/container');
const app = require('../src/app');

const fixedNow = Date.parse('2026-07-01T05:00:00.000Z');

function sign(role = 'ADMIN', id = 1) {
  return jwt.sign(
    { sub: id, email: `${role.toLowerCase()}@example.com`, role, type: 'access' },
    process.env.JWT_ACCESS_SECRET,
    { expiresIn: '1h' },
  );
}

function row(overrides = {}) {
  return {
    booking_id: 42,
    booking_number: 'TX202607010001',
    booking_status: 'PENDING',
    service_type_code: 'AIRPORT_PICKUP',
    scheduled_pickup_at_text: '2026-07-01 12:00:00',
    flight_number: 'TG409',
    flight_scheduled_arrival_at_text: '2026-07-01 12:00:00',
    flight_estimated_arrival_at_text: null,
    flight_status: FLIGHT_STATUS.SCHEDULED,
    last_synced_at_text: null,
    sync_status: 'NEVER',
    ...overrides,
  };
}

function createWorker({
  rows = [row()],
  enabled = true,
  providerConfigured = true,
  syncImpl,
  retryBaseMs = 1,
  maxRetries = 3,
} = {}) {
  const calls = { selected: [], synced: [] };
  const repository = {
    async listAutoSyncCandidates(input) {
      calls.selected.push(input);
      return rows;
    },
  };
  const service = {
    flightService: {
      isProviderConfigured: () => providerConfigured,
    },
    async syncFlight(bookingId) {
      calls.synced.push(bookingId);
      if (syncImpl) return syncImpl(bookingId, calls.synced.length);
      return { bookingId, syncStatus: 'SUCCESS' };
    },
  };
  const worker = new FlightSyncWorker({
    flightMonitorRepository: repository,
    adminFlightMonitorService: service,
    nowFn: () => fixedNow,
    config: {
      enabled,
      batchSize: 2,
      lookbackHours: 6,
      lookaheadHours: 48,
      maxRetries,
      retryBaseMs,
    },
  });
  return { worker, calls };
}

test('worker disabled by default style config skips without provider calls', async () => {
  const { worker, calls } = createWorker({ enabled: false });
  const summary = await worker.runCycle();
  assert.equal(summary.skipped, 1);
  assert.equal(calls.selected.length, 0);
  assert.equal(calls.synced.length, 0);
});

test('missing provider config safely skips cycle', async () => {
  const { worker, calls } = createWorker({ providerConfigured: false });
  const summary = await worker.runCycle();
  assert.equal(summary.configMissing, true);
  assert.equal(calls.selected.length, 0);
  assert.equal(calls.synced.length, 0);
});

test('candidate selection applies dynamic eligibility, priority, and batch limit', async () => {
  const { worker, calls } = createWorker({
    rows: [
      row({ booking_id: 1, flight_estimated_arrival_at_text: '2026-07-03 13:10:00' }),
      row({ booking_id: 2, flight_estimated_arrival_at_text: '2026-07-01 12:30:00', flight_status: FLIGHT_STATUS.DELAYED }),
      row({ booking_id: 3, flight_estimated_arrival_at_text: '2026-07-01 13:00:00' }),
      row({ booking_id: 4, flight_estimated_arrival_at_text: '2026-07-01 12:00:00', last_synced_at_text: '2026-07-01 11:58:00' }),
    ],
  });

  const summary = await worker.runCycle();
  assert.equal(summary.selected, 2);
  assert.deepEqual(calls.synced, [2, 3]);
});

test('dynamic eligibility windows handle near, mid, far, outside, and final statuses', () => {
  const { worker } = createWorker();
  assert.equal(worker.isEligibleByPolicy(row({ flight_estimated_arrival_at_text: '2026-07-01 13:00:00' })), true);
  assert.equal(worker.isEligibleByPolicy(row({
    flight_estimated_arrival_at_text: '2026-07-01 17:00:00',
    last_synced_at_text: '2026-07-01 11:44:00',
  })), true);
  assert.equal(worker.isEligibleByPolicy(row({
    flight_estimated_arrival_at_text: '2026-07-02 18:00:00',
    last_synced_at_text: '2026-07-01 11:05:00',
  })), false);
  assert.equal(worker.isEligibleByPolicy(row({ flight_estimated_arrival_at_text: '2026-07-04 12:00:00' })), false);
  assert.equal(worker.isEligibleByPolicy(row({
    flight_status: FLIGHT_STATUS.LANDED,
    sync_status: 'SUCCESS',
  })), false);
  assert.equal(worker.isEligibleByPolicy(row({
    flight_status: FLIGHT_STATUS.CANCELLED,
    sync_status: 'NEVER',
  })), true);
});

test('one failure does not stop batch', async () => {
  const { worker, calls } = createWorker({
    rows: [row({ booking_id: 1 }), row({ booking_id: 2 })],
    syncImpl(bookingId) {
      if (bookingId === 1) throw new AppError('Not found', { errorCode: ERROR_CODES.FLIGHT_NOT_FOUND });
      return { bookingId, syncStatus: 'SUCCESS' };
    },
  });
  const summary = await worker.runCycle();
  assert.equal(summary.failed, 1);
  assert.equal(summary.succeeded, 1);
  assert.deepEqual(calls.synced, [1, 2]);
});

test('rate limit stops remaining provider calls in current cycle', async () => {
  const { worker, calls } = createWorker({
    rows: [row({ booking_id: 1 }), row({ booking_id: 2 })],
    syncImpl() {
      throw new AppError('Rate limited', { errorCode: ERROR_CODES.FLIGHT_PROVIDER_RATE_LIMITED });
    },
  });
  const summary = await worker.runCycle();
  assert.equal(summary.rateLimited, true);
  assert.equal(summary.failed, 1);
  assert.equal(summary.skipped, 1);
  assert.deepEqual(calls.synced, [1]);
});

test('transient retry is bounded', async () => {
  const { worker, calls } = createWorker({
    rows: [row({ booking_id: 1 })],
    maxRetries: 3,
    syncImpl() {
      throw new AppError('Timeout', { errorCode: ERROR_CODES.FLIGHT_PROVIDER_TIMEOUT });
    },
  });
  const summary = await worker.runCycle();
  assert.equal(summary.failed, 1);
  assert.equal(calls.synced.length, 3);
});

test('manual cooldown conflict is treated as skipped auto item', async () => {
  const { worker } = createWorker({
    rows: [row({ booking_id: 1 })],
    syncImpl() {
      throw new AppError('Too soon', { errorCode: ERROR_CODES.RATE_LIMIT });
    },
  });
  const summary = await worker.runCycle();
  assert.equal(summary.skipped, 1);
  assert.equal(summary.failed, 0);
});

test('scheduler prevents overlapping cycles and stops timer cleanly', async () => {
  let resolveRun;
  const worker = {
    runCycle() {
      return new Promise((resolve) => {
        resolveRun = resolve;
      });
    },
  };
  const scheduler = new FlightSyncSchedulerService(
    worker,
    { enabled: true, intervalMs: 300000, batchSize: 20 },
    () => true,
  );
  const first = scheduler.runCycle();
  const overlap = await scheduler.runCycle();
  assert.equal(overlap.skippedReason, 'ALREADY_RUNNING');
  resolveRun({ selected: 0, succeeded: 0, skipped: 0, failed: 0, rateLimited: false, configMissing: false, durationMs: 1 });
  await first;
  scheduler.start();
  assert.ok(scheduler.timer);
  scheduler.stop();
  assert.equal(scheduler.timer, null);
});

test('sync-status endpoint allows ADMIN and SUPER_ADMIN and rejects others', async () => {
  container.register('flightSyncSchedulerService', () => ({
    getStatus() {
      return {
        enabled: true,
        running: false,
        providerConfigured: false,
        intervalMs: 300000,
        lastCycleStartedAt: null,
        lastCycleCompletedAt: null,
        lastCycle: null,
        nextExpectedRunAt: null,
      };
    },
  }));

  const admin = await request(app)
    .get('/api/v1/admin/flights/sync-status')
    .set('Authorization', `Bearer ${sign('ADMIN')}`);
  assert.equal(admin.status, 200);
  assert.equal(admin.body.data.providerConfigured, false);
  assert.ok(!('apiKey' in admin.body.data));

  const superAdmin = await request(app)
    .get('/api/v1/admin/flights/sync-status')
    .set('Authorization', `Bearer ${sign('SUPER_ADMIN')}`);
  assert.equal(superAdmin.status, 200);

  const driver = await request(app)
    .get('/api/v1/admin/flights/sync-status')
    .set('Authorization', `Bearer ${sign('DRIVER', 9)}`);
  assert.equal(driver.status, 403);

  const guest = await request(app).get('/api/v1/admin/flights/sync-status');
  assert.equal(guest.status, 401);
});

test('run-now endpoint returns safe summary', async () => {
  container.register('flightSyncSchedulerService', () => ({
    async runNow() {
      return {
        selected: 1,
        succeeded: 1,
        skipped: 0,
        failed: 0,
        rateLimited: false,
        configMissing: false,
        durationMs: 12,
      };
    },
  }));

  const res = await request(app)
    .post('/api/v1/admin/flights/run-sync-cycle')
    .set('Authorization', `Bearer ${sign('ADMIN')}`);
  assert.equal(res.status, 200);
  assert.equal(res.body.data.succeeded, 1);
  assert.ok(!('providerPayload' in res.body.data));
});
