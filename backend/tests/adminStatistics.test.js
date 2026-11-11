const { test } = require('node:test');
const assert = require('node:assert/strict');
const { dateRange, getStatistics, summarize } = require('../src/services/adminStatistics.service');

test('Bangkok calendar dates reject invalid or overly broad ranges', () => {
  for (const [from, to] of [
    ['2026-02-29', '2026-03-01'],
    ['2026-12-01', '2026-11-30'],
    ['2026-01-01', '2027-01-02'],
    [['2026-01-01'], '2026-01-01'],
  ]) {
    assert.throws(() => dateRange(from, to), { errorCode: 'STATISTICS_INVALID_RANGE' });
  }
  assert.equal(dateRange('2024-01-01', '2024-12-31').until, '2025-01-01');
});

test('daily, monthly and contact groups preserve trip and passenger counts', () => {
  const result = summarize([
    { day: '2026-10-31', phoneHint: '+8210', flight: '7C2551', service: 'AIRPORT_PICKUP', bookings: '2', passengers: '4', nameSign: '2' },
    { day: '2026-11-02', phoneHint: '00821', flight: '7C2551', service: 'AIRPORT_PICKUP', bookings: '1', passengers: '2' },
    { day: '2026-11-02', phoneHint: '+1202', service: 'GOLF_TRANSFER', bookings: 1, passengers: 3, golfDriver: 1 },
    { day: '2026-11-02', phoneHint: null, service: 'CITY_TRANSFER', bookings: 1, passengers: 1, femaleDriver: 1, coupon: 1 },
  ], dateRange('2026-10-31', '2026-11-02'));
  assert.deepEqual(result.daily.map(r => r.bookings), [2, 0, 3]);
  assert.deepEqual(result.monthly.map(r => r.passengers), [4, 6]);
  assert.deepEqual(result.totals, {
    bookings: 5, passengers: 10, options: { nameSign: 2, femaleDriver: 1, golfDriver: 1, coupon: 1 },
  });
  assert.deepEqual(result.countries.map(r => [r.key, r.passengers]), [['+82', 6], ['+1', 3], [null, 1]]);
  assert.equal(result.flights[0].bookings, 3);
  assert.equal(result.services.length, 3);
  assert.doesNotMatch(JSON.stringify(result), /phoneHint|8210|00821|1202/);
});

test('SQL uses inclusive Bangkok dates with an exclusive upper bound and filters ended trips', async () => {
  const data = await getStatistics('2026-12-31', '2026-12-31', {
    async query(sql, params) {
      assert.deepEqual(params, ['2026-12-31 00:00:00', '2027-01-01 00:00:00']);
      assert.match(sql, /b\.scheduled_pickup_at >= \? AND b\.scheduled_pickup_at < \?/);
      assert.match(sql, /b\.status IN \('SETTLEMENT_PENDING', 'COMPLETED'\)/);
      return [[]];
    },
  });
  assert.equal(data.daily.length, 1);
  assert.equal(data.totals.bookings, 0);
});

test('MariaDB returns ended trips without double-counting options', {
  skip: !process.env.GUEST_LOOKUP_TEST_DB,
}, async () => {
  const database = process.env.GUEST_LOOKUP_TEST_DB;
  assert.match(database, /^qa_guest_lookup_[a-z0-9_]+$/);
  const mysql = require('mysql2/promise');
  const connection = await mysql.createConnection({
    host: process.env.GUEST_LOOKUP_TEST_DB_HOST || '127.0.0.1',
    port: Number(process.env.GUEST_LOOKUP_TEST_DB_PORT || 33317),
    user: process.env.GUEST_LOOKUP_TEST_DB_USER || 'root',
    password: process.env.GUEST_LOOKUP_TEST_DB_PASSWORD || '',
    database,
  });
  try {
    const statements = [
      'CREATE TEMPORARY TABLE bookings (id INT, customer_phone VARCHAR(32), service_type_id INT, status VARCHAR(30), prefer_female_driver INT, is_archived INT, deleted_at DATETIME, scheduled_pickup_at DATETIME)',
      'CREATE TEMPORARY TABLE service_types (id INT, code VARCHAR(30))',
      'CREATE TEMPORARY TABLE booking_passengers (booking_id INT, adults INT, children INT, infants INT, deleted_at DATETIME)',
      'CREATE TEMPORARY TABLE booking_transfer_details (booking_id INT, flight_number VARCHAR(20), driver_included INT, deleted_at DATETIME)',
      'CREATE TEMPORARY TABLE booking_charge_items (booking_id INT, charge_type VARCHAR(30), deleted_at DATETIME)',
      "INSERT INTO service_types VALUES (1, 'AIRPORT_PICKUP'), (2, 'GOLF_TRANSFER')",
      "INSERT INTO bookings VALUES (1,'+82 10-0000-0000',1,'COMPLETED',1,0,NULL,'2026-10-31 23:59:59'), (2,'0812345678',2,'SETTLEMENT_PENDING',0,0,NULL,'2026-10-31 00:00:00'), (3,NULL,1,'CANCELLED',0,0,NULL,'2026-10-31'), (4,NULL,1,'COMPLETED',0,1,NULL,'2026-10-31'), (5,NULL,1,'COMPLETED',0,0,'2026-11-01','2026-10-31'), (6,NULL,1,'COMPLETED',0,0,NULL,'2026-11-01 00:00:00')",
      'INSERT INTO booking_passengers VALUES (1,2,1,1,NULL), (2,1,0,0,NULL)',
      "INSERT INTO booking_transfer_details VALUES (1,'7c 2551',0,NULL), (2,NULL,1,NULL)",
      "INSERT INTO booking_charge_items VALUES (1,'NAME_SIGN',NULL), (1,'NAME_SIGN',NULL), (2,'COUPON','2026-11-01')",
    ];
    for (const sql of statements) await connection.query(sql);
    const result = await getStatistics('2026-10-31', '2026-10-31', connection);
    assert.deepEqual(result.totals, {
      bookings: 2, passengers: 5, options: { nameSign: 1, femaleDriver: 1, golfDriver: 1, coupon: 0 },
    });
    assert.deepEqual(result.countries.map(({ key, passengers }) => [key, passengers]), [['+82', 4], [null, 1]]);
    assert.deepEqual(result.flights.map(({ key }) => key), ['7C2551']);
  } finally {
    await connection.end();
  }
});
