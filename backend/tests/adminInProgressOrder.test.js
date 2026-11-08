const test = require('node:test');
const assert = require('node:assert/strict');
const BookingRepository = require('../src/repositories/booking.repository');

test('in-progress ordering is chronological before pagination and retains its status filter', async () => {
  const calls = [];
  const repository = new BookingRepository({
    query: async (sql, params) => { calls.push({ sql, params }); return [[]]; },
  });
  for (const offset of [0, 20]) {
    await repository.findAdminBookings(
      { view: 'in_progress', inProgressOnly: true, excludeTerminalStatuses: true },
      { limit: 20, offset },
    );
  }
  for (const [i, { sql, params }] of calls.entries()) {
    assert.match(sql, /b\.status IN \('DRIVER_ASSIGNED', 'ON_ROUTE', 'DRIVER_ARRIVED', 'PICKED_UP'\)/);
    assert.match(sql, /ORDER BY\s+b\.scheduled_pickup_at ASC,\s+b\.booking_number ASC\s+LIMIT \? OFFSET \?/);
    assert.deepEqual(params.slice(-2), [20, i * 20]);
  }
});

test('in-progress uses booking number ascending to stabilize equal pickup times', () => {
  const repository = new BookingRepository({});
  assert.match(repository.adminQueueOrderSql('in_progress'), /scheduled_pickup_at ASC,\s+b\.booking_number ASC/);
});

test('other booking tabs retain their existing ordering contracts', () => {
  const repository = new BookingRepository({});
  for (const view of ['needs_action', 'issues']) {
    assert.match(repository.adminQueueOrderSql(view), /scheduled_pickup_at ASC,\s+b\.booking_number ASC/);
  }
  assert.match(repository.adminQueueOrderSql('settlement'), /commission_status[\s\S]+scheduled_pickup_at DESC/);
  for (const view of [undefined, 'all', 'today', 'upcoming', 'cancelled']) {
    const sql = repository.adminQueueOrderSql(view);
    assert.match(sql, /THEN b\.created_at END DESC/);
    assert.match(sql, /THEN b\.scheduled_pickup_at END DESC/);
    assert.match(sql, /b\.booking_number DESC/);
  }
});
