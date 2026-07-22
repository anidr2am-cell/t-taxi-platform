const { test } = require('node:test');
const assert = require('node:assert/strict');

process.env.NODE_ENV = process.env.NODE_ENV || 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const UrgentNegotiationSchedulerService = require('../src/services/urgentNegotiationScheduler.service');

test('urgent negotiation scheduler prevents overlapping cycles and stops timer cleanly', async () => {
  let resolveRun;
  const worker = {
    runCycle() {
      return new Promise((resolve) => {
        resolveRun = resolve;
      });
    },
  };
  const scheduler = new UrgentNegotiationSchedulerService(
    worker,
    { enabled: true, intervalMs: 30000, batchSize: 20 },
  );

  const first = scheduler.runCycle();
  const overlap = await scheduler.runCycle();
  assert.equal(overlap.skippedReason, 'ALREADY_RUNNING');

  resolveRun({
    lockedSelected: 1,
    lockedProcessed: 1,
    lockedFailed: 0,
    customerSelected: 0,
    customerProcessed: 0,
    customerFailed: 0,
    durationMs: 3,
  });
  await first;

  scheduler.start();
  assert.ok(scheduler.timer);
  scheduler.stop();
  assert.equal(scheduler.timer, null);
});

test('urgent negotiation scheduler does not schedule when disabled', () => {
  const scheduler = new UrgentNegotiationSchedulerService(
    { async runCycle() { return {}; } },
    { enabled: false, intervalMs: 30000, batchSize: 20 },
  );
  scheduler.start();
  assert.equal(scheduler.timer, null);
  assert.equal(scheduler.started, true);
});
