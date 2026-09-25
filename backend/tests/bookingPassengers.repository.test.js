const { test } = require('node:test');
const assert = require('node:assert/strict');
const BookingRepository = require('../src/repositories/booking.repository');

test('passenger update targets the booking, not the infant count', async () => {
  const rows = new Map([[305, [2, 1, 1]], [1, [4, 0, 0]]]);
  const conn = {
    async query(sql, values) {
      assert.match(sql, /UPDATE booking_passengers/);
      const [adults, children, infants, bookingId] = values;
      if (!rows.has(bookingId)) return [{ affectedRows: 0 }];
      rows.set(bookingId, [adults, children, infants]);
      return [{ affectedRows: 1 }];
    },
  };
  await new BookingRepository({}).updatePassengers(conn, 305, { adults: 2, children: 2, infants: 1 });
  assert.deepEqual(rows.get(305), [2, 2, 1]);
  assert.deepEqual(rows.get(1), [4, 0, 0]);
});

test('missing passenger row is inserted with the booking ID first', async () => {
  const calls = [];
  const conn = { async query(sql, values) { calls.push({ sql, values }); return [{ affectedRows: 0 }]; } };
  await new BookingRepository({}).updatePassengers(conn, 305, { adults: 2, children: 1, infants: 0 });
  assert.equal(calls.length, 2);
  assert.match(calls[1].sql, /INSERT INTO booking_passengers/);
  assert.deepEqual(calls[1].values, [305, 2, 1, 0]);
});
