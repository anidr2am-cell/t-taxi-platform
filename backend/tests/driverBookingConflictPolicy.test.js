const { test } = require('node:test');
const assert = require('node:assert/strict');

const ERROR_CODES = require('../src/constants/errorCodes');
const {
  assertNoPickupTimeConflict,
  PICKUP_CONFLICT_WINDOW_MS,
} = require('../src/policies/driverBookingConflictPolicy');

function expectConflict(fn) {
  assert.throws(
    fn,
    (err) => err.errorCode === ERROR_CODES.DRIVER_BOOKING_TIME_CONFLICT,
  );
}

test('PICKUP_CONFLICT_WINDOW_MS is exactly 3 hours', () => {
  assert.equal(PICKUP_CONFLICT_WINDOW_MS, 3 * 60 * 60 * 1000);
});

test('blocks 10:00 existing vs 12:59 new pickup', () => {
  expectConflict(() => assertNoPickupTimeConflict(
    [{ id: 1, scheduled_pickup_at: '2026-07-13 10:00:00' }],
    '2026-07-13 12:59:00',
  ));
});

test('allows 10:00 existing vs 13:00 new pickup', () => {
  assert.doesNotThrow(() => assertNoPickupTimeConflict(
    [{ id: 1, scheduled_pickup_at: '2026-07-13 10:00:00' }],
    '2026-07-13 13:00:00',
  ));
});

test('allows 10:00 existing vs 13:01 new pickup', () => {
  assert.doesNotThrow(() => assertNoPickupTimeConflict(
    [{ id: 1, scheduled_pickup_at: '2026-07-13 10:00:00' }],
    '2026-07-13 13:01:00',
  ));
});

test('blocks 15:00 existing vs 13:00 new pickup', () => {
  expectConflict(() => assertNoPickupTimeConflict(
    [{ id: 1, scheduled_pickup_at: '2026-07-13 15:00:00' }],
    '2026-07-13 13:00:00',
  ));
});

test('allows 15:00 existing vs 12:00 new pickup', () => {
  assert.doesNotThrow(() => assertNoPickupTimeConflict(
    [{ id: 1, scheduled_pickup_at: '2026-07-13 15:00:00' }],
    '2026-07-13 12:00:00',
  ));
});

test('allows 15:00 existing vs 11:30 new pickup', () => {
  assert.doesNotThrow(() => assertNoPickupTimeConflict(
    [{ id: 1, scheduled_pickup_at: '2026-07-13 15:00:00' }],
    '2026-07-13 11:30:00',
  ));
});

test('blocks when any of multiple future assignments is under 3 hours apart', () => {
  expectConflict(() => assertNoPickupTimeConflict(
    [
      { id: 1, scheduled_pickup_at: '2026-07-13 08:00:00' },
      { id: 2, scheduled_pickup_at: '2026-07-13 12:30:00' },
    ],
    '2026-07-13 10:00:00',
  ));
});

test('allows when all assignments are at least 3 hours apart', () => {
  assert.doesNotThrow(() => assertNoPickupTimeConflict(
    [
      { id: 1, scheduled_pickup_at: '2026-07-13 06:00:00' },
      { id: 2, scheduled_pickup_at: '2026-07-13 14:00:00' },
    ],
    '2026-07-13 10:00:00',
  ));
});

test('allows when no active assignment rows are returned', () => {
  assert.doesNotThrow(() => assertNoPickupTimeConflict([], '2026-07-13 10:00:00'));
});

test('ignores excluded booking id during comparison', () => {
  assert.doesNotThrow(() => assertNoPickupTimeConflict(
    [{ id: 10, scheduled_pickup_at: '2026-07-13 11:00:00' }],
    '2026-07-13 10:00:00',
    { excludeBookingId: 10 },
  ));
});

test('rejects null target pickup time', () => {
  expectConflict(() => assertNoPickupTimeConflict(
    [{ id: 1, scheduled_pickup_at: '2026-07-13 10:00:00' }],
    null,
  ));
});

test('rejects existing assignment with null pickup time instead of skipping', () => {
  expectConflict(() => assertNoPickupTimeConflict(
    [{ id: 1, scheduled_pickup_at: null }],
    '2026-07-13 10:00:00',
  ));
});

test('findActiveAssignmentPickupsForConflict SQL excludes terminal booking statuses', () => {
  const { readFileSync } = require('node:fs');
  const { join } = require('node:path');
  const source = readFileSync(
    join(__dirname, '../src/repositories/driver.repository.js'),
    'utf8',
  );
  const fnStart = source.indexOf('async findActiveAssignmentPickupsForConflict');
  assert.ok(fnStart >= 0);
  const fnBody = source.slice(fnStart, fnStart + 1200);
  assert.match(fnBody, /bda\.is_active = 1/);
  assert.match(fnBody, /bda\.deleted_at IS NULL/);
  assert.match(fnBody, /bda\.status IN \('ASSIGNED', 'ACCEPTED'\)/);
  assert.match(fnBody, /b\.status IN \('DRIVER_ASSIGNED', 'ON_ROUTE', 'DRIVER_ARRIVED', 'PICKED_UP', 'SETTLEMENT_PENDING'\)/);
  assert.doesNotMatch(fnBody, /COMPLETED/);
  assert.doesNotMatch(fnBody, /CANCELLED/);
  assert.doesNotMatch(fnBody, /NO_SHOW/);
});

test('hasActiveJob SQL includes future assigned bookings, not only in-progress trips', () => {
  const { readFileSync } = require('node:fs');
  const { join } = require('node:path');
  const source = readFileSync(
    join(__dirname, '../src/repositories/driver.repository.js'),
    'utf8',
  );
  const fnStart = source.indexOf('async hasActiveJob');
  assert.ok(fnStart >= 0);
  const fnBody = source.slice(fnStart, fnStart + 700);
  assert.match(fnBody, /bda\.status IN \('ASSIGNED', 'ACCEPTED'\)/);
  assert.match(fnBody, /'DRIVER_ASSIGNED'/);
  assert.doesNotMatch(fnBody, /scheduled_pickup_at >=/);
  assert.doesNotMatch(fnBody, /CURDATE\(\)/);
});
