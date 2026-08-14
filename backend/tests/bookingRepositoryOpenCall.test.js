const test = require('node:test');
const assert = require('node:assert/strict');

process.env.NODE_ENV = process.env.NODE_ENV || 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const BookingRepository = require('../src/repositories/booking.repository');

function assertNameSignRequestedUsesExistsSubquery(sql) {
  assert.doesNotMatch(sql, /b\.name_sign_requested/);
  assert.match(
    sql,
    /EXISTS\s+\([\s\S]*FROM booking_charge_items bci[\s\S]*charge_type = 'NAME_SIGN'[\s\S]*\) AS name_sign_requested/,
  );
}

function assertNameSignAmountUsesSumSubquery(sql) {
  assert.match(
    sql,
    /SELECT COALESCE\(SUM\(bci\.amount\), 0\)[\s\S]*FROM booking_charge_items bci[\s\S]*charge_type = 'NAME_SIGN'[\s\S]*\) AS name_sign_amount/,
  );
}

test('findOpenDriverCallByBookingId selects name_sign_requested via charge item EXISTS', async () => {
  let capturedSql = '';
  let capturedParams = [];
  const conn = {
    async query(sql, params) {
      capturedSql = sql;
      capturedParams = params;
      return [[{ booking_number: 'TX202607010001', name_sign_requested: 0 }]];
    },
  };
  const repository = new BookingRepository({});

  const row = await repository.findOpenDriverCallByBookingId(conn, 42);

  assert.equal(row.booking_number, 'TX202607010001');
  assert.deepEqual(capturedParams, [42]);
  assertNameSignRequestedUsesExistsSubquery(capturedSql);
  assertNameSignAmountUsesSumSubquery(capturedSql);
  assert.match(capturedSql, /WHERE b\.id = \?/);
  assert.match(capturedSql, /AND b\.status = 'OPEN'/);
  assert.match(capturedSql, /b\.vehicle_type_id/);
});

test('findOpenDriverCallByBookingId exposes vehicle_type_id for contact verified dispatch', async () => {
  const conn = {
    async query(_sql, _params) {
      return [[{
        booking_number: 'TX202608140002',
        vehicle_type_id: 2,
        vehicle_type_code: 'SUV',
        vehicle_type_name: 'SUV',
      }]];
    },
  };
  const repository = new BookingRepository({});

  const row = await repository.findOpenDriverCallByBookingId(conn, 192);

  assert.equal(row.vehicle_type_id, 2);
  assert.equal(row.vehicle_type_code, 'SUV');
});

test('findOpenDriverCallsForDriver shares the same name_sign_requested EXISTS select', async () => {
  let capturedSql = '';
  const pool = {
    async query(sql) {
      capturedSql = sql;
      return [[]];
    },
  };
  const repository = new BookingRepository(pool);

  await repository.findOpenDriverCallsForDriver(99);

  assertNameSignRequestedUsesExistsSubquery(capturedSql);
  assertNameSignAmountUsesSumSubquery(capturedSql);
  assert.match(capturedSql, /d\.user_id = \?/);
  assert.match(capturedSql, /TIMESTAMPDIFF\(MINUTE, own_b\.scheduled_pickup_at, b\.scheduled_pickup_at\)/);
});
