const test = require('node:test');
const assert = require('node:assert/strict');

process.env.NODE_ENV = process.env.NODE_ENV || 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'tride_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret';

const BookingIdempotencyRepository = require('../src/repositories/bookingIdempotency.repository');
const BookingIdempotencyCleanupWorker = require('../src/workers/bookingIdempotencyCleanup.worker');
const BookingIdempotencyCleanupSchedulerService = require('../src/services/bookingIdempotencyCleanupScheduler.service');

function createConn() {
  const queries = [];
  return {
    queries,
    released: false,
    async query(sql, params) {
      queries.push({ sql, params });
      if (sql.includes('DELETE FROM booking_idempotency_keys')) {
        return [{ affectedRows: params?.[0] === 500 ? 3 : 1 }];
      }
      return [{ affectedRows: 0 }];
    },
    release() {
      this.released = true;
    },
  };
}

test('deleteExpiredBatch removes only expired rows with batch limit', async () => {
  const conn = createConn();
  const repository = new BookingIdempotencyRepository();
  const deleted = await repository.deleteExpiredBatch(conn, 500);

  assert.equal(deleted, 3);
  assert.match(conn.queries[0].sql, /expires_at < UTC_TIMESTAMP\(\)/);
  assert.equal(conn.queries[0].params[0], 500);
});

test('booking idempotency cleanup worker returns deleted count', async () => {
  const conn = createConn();
  const worker = new BookingIdempotencyCleanupWorker({
    pool: {
      async getConnection() {
        return conn;
      },
    },
    bookingIdempotencyRepository: new BookingIdempotencyRepository(),
    config: { batchSize: 500 },
    nowFn: () => 1000,
  });

  const summary = await worker.runCycle();
  assert.equal(summary.deleted, 3);
  assert.equal(summary.durationMs, 0);
  assert.equal(conn.released, true);
});

test('booking idempotency cleanup scheduler skips overlapping cycles', async () => {
  let resolveCycle;
  const worker = {
    runCycle: () => new Promise((resolve) => {
      resolveCycle = resolve;
    }),
  };
  const scheduler = new BookingIdempotencyCleanupSchedulerService(worker, {
    enabled: true,
    intervalMs: 60000,
    batchSize: 500,
  });

  const first = scheduler.runCycle();
  const second = scheduler.runCycle();
  resolveCycle({ deleted: 2, durationMs: 5 });
  const firstResult = await first;
  const secondResult = await second;

  assert.equal(firstResult.deleted, 2);
  assert.equal(secondResult.skippedReason, 'ALREADY_RUNNING');
  scheduler.stop();
});
