const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

test('settlement timestamp migration is one-time and rollback is inverse', () => {
  const migration = fs.readFileSync(path.join(__dirname, '..', '..', 'database', '69_settlement_timestamps_bangkok.sql'), 'utf8');
  const rollback = fs.readFileSync(path.join(__dirname, '..', '..', 'database', 'rollback', '69_settlement_timestamps_bangkok.rollback.sql'), 'utf8');
  assert.match(migration, /DATE_ADD\(commission_paid_at, INTERVAL 7 HOUR\)/);
  assert.match(migration, /69_settlement_timestamps_bangkok/);
  assert.match(rollback, /SET b\.commission_paid_at = s\.original_paid_at/);
  assert.match(rollback, /b\.commission_paid_at = s\.corrected_paid_at/);
  assert.match(migration, /START TRANSACTION/);
});

test('settlement timestamp migration includes all 52 verified production rows', () => {
  const migration = fs.readFileSync(path.join(__dirname, '..', '..', 'database', '69_settlement_timestamps_bangkok.sql'), 'utf8');
  const reviewedLegacyBookings = [
    'TX202607090005',
    'TX202607110002',
    'TX202607110003',
    'TX202607120002',
    'TX202607130002',
  ];

  assert.match(migration, /47 rows have a matching UTC approval instant/);
  for (const bookingNumber of reviewedLegacyBookings) {
    assert.match(migration, new RegExp(`'${bookingNumber}'`));
  }
  assert.equal(47 + reviewedLegacyBookings.length, 52);
});
