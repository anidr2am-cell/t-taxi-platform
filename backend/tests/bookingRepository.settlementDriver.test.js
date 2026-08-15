process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const test = require('node:test');
const assert = require('node:assert/strict');
const BookingRepository = require('../src/repositories/booking.repository');

test('findSettlementNotificationDriver prefers completed assignment over cancelled history', async () => {
  let capturedSql = '';
  const repo = new BookingRepository({
    async query(sql, params) {
      capturedSql = sql;
      assert.deepEqual(params, [7]);
      return [[{ driver_id: 11, driver_user_id: 15 }]];
    },
  });

  const row = await repo.findSettlementNotificationDriver(null, 7);

  assert.match(capturedSql, /CASE WHEN bda2\.status = 'COMPLETED' THEN 0 ELSE 1 END/);
  assert.match(capturedSql, /COALESCE\(bda\.driver_id, b\.driver_id\)/);
  assert.deepEqual(row, { driver_id: 11, driver_user_id: 15 });
});

test('findSettlementNotificationDriver returns null when no driver user can be resolved', async () => {
  const repo = new BookingRepository({
    async query() {
      return [[{ driver_id: null, driver_user_id: null }]];
    },
  });

  const row = await repo.findSettlementNotificationDriver(null, 7);
  assert.equal(row, null);
});

test('findSettlementNotificationDriver falls back to bookings.driver_id via COALESCE', async () => {
  const repo = new BookingRepository({
    async query() {
      return [[{ driver_id: 5, driver_user_id: 44 }]];
    },
  });

  const row = await repo.findSettlementNotificationDriver(null, 7);
  assert.deepEqual(row, { driver_id: 5, driver_user_id: 44 });
});
