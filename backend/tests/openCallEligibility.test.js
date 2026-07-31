process.env.NODE_ENV = process.env.NODE_ENV || 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');

const DriverRepository = require('../src/repositories/driver.repository');
const BookingRepository = require('../src/repositories/booking.repository');
const {
  PICKUP_CONFLICT_MIN_GAP_MINUTES,
  assertNoPickupTimeConflict,
} = require('../src/policies/driverBookingConflictPolicy');

function readSource(relativePath) {
  return readFileSync(join(__dirname, relativePath), 'utf8');
}

function mirrorsSqlPickupConflict(existingPickups, newPickupAt) {
  if (newPickupAt == null) {
    return existingPickups.length > 0;
  }
  for (const scheduledPickupAt of existingPickups) {
    if (scheduledPickupAt == null) {
      return true;
    }
    const diffMinutes = Math.abs(
      (new Date(newPickupAt).getTime() - new Date(scheduledPickupAt).getTime()) / (60 * 1000),
    );
    if (diffMinutes <= PICKUP_CONFLICT_MIN_GAP_MINUTES) {
      return true;
    }
  }
  return false;
}

test('listEligibleForOpenBooking uses 60-minute pickup conflict gap from policy', async () => {
  let capturedSql = '';
  let capturedParams = [];
  const conn = {
    async query(sql, params) {
      capturedSql = sql;
      capturedParams = params;
      return [[]];
    },
  };
  const repository = new DriverRepository({});

  await repository.listEligibleForOpenBooking(conn, 3, {
    scheduledPickupAt: '2026-07-31 21:10:00',
    excludeReleasedBookingId: 173,
  });

  assert.match(capturedSql, /TIMESTAMPDIFF\(MINUTE, b\.scheduled_pickup_at, \?\)/);
  assert.match(capturedSql, /<= \?/);
  assert.equal(capturedParams[0], 3);
  assert.equal(capturedParams[1], '2026-07-31 21:10:00');
  assert.equal(capturedParams[2], '2026-07-31 21:10:00');
  assert.equal(capturedParams[3], PICKUP_CONFLICT_MIN_GAP_MINUTES);
  assert.equal(capturedParams[4], 173);
  assert.equal(capturedParams[5], 173);
});

test('findOpenDriverCallsForDriver compares each open call pickup against active assignments', async () => {
  let capturedSql = '';
  let capturedParams = [];
  const pool = {
    async query(sql, params) {
      capturedSql = sql;
      capturedParams = params;
      return [[]];
    },
  };
  const repository = new BookingRepository(pool);

  await repository.findOpenDriverCallsForDriver(4);

  assert.match(
    capturedSql,
    /TIMESTAMPDIFF\(MINUTE, own_b\.scheduled_pickup_at, b\.scheduled_pickup_at\)/,
  );
  assert.equal(capturedParams[0], 4);
  assert.equal(capturedParams[1], PICKUP_CONFLICT_MIN_GAP_MINUTES);
});

test('driver_id=2 scenario: 10-minute gap remains excluded', () => {
  const existingPickups = ['2026-07-31 21:00:00'];
  const newPickupAt = '2026-07-31 21:10:00';

  assert.equal(mirrorsSqlPickupConflict(existingPickups, newPickupAt), true);
  assert.throws(
    () => assertNoPickupTimeConflict(
      [{ id: 172, scheduled_pickup_at: existingPickups[0] }],
      newPickupAt,
    ),
  );
});

test('driver_id=2 scenario: 90-minute gap becomes eligible', () => {
  const existingPickups = ['2026-07-31 21:00:00'];
  const newPickupAt = '2026-07-31 22:30:00';

  assert.equal(mirrorsSqlPickupConflict(existingPickups, newPickupAt), false);
  assert.doesNotThrow(
    () => assertNoPickupTimeConflict(
      [{ id: 172, scheduled_pickup_at: existingPickups[0] }],
      newPickupAt,
    ),
  );
});

test('drivers without active assignments remain eligible', () => {
  assert.equal(mirrorsSqlPickupConflict([], '2026-07-31 21:10:00'), false);
  assert.doesNotThrow(
    () => assertNoPickupTimeConflict([], '2026-07-31 21:10:00'),
  );
});

test('listEligibleForOpenBooking SQL keeps pickup conflict filter on active assignments', () => {
  const driverSource = readSource('../src/repositories/driver.repository.js');
  const listStart = driverSource.indexOf('async listEligibleForOpenBooking');
  const listBody = driverSource.slice(listStart, listStart + 2200);

  assert.match(listBody, /bda\.status IN \('ASSIGNED', 'ACCEPTED'\)/);
  assert.match(
    listBody,
    /'DRIVER_ASSIGNED', 'ON_ROUTE', 'DRIVER_ARRIVED', 'PICKED_UP', 'SETTLEMENT_PENDING'/,
  );
  assert.match(listBody, /TIMESTAMPDIFF\(MINUTE, b\.scheduled_pickup_at, \?\)/);
});
