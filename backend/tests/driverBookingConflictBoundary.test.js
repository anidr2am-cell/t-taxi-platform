process.env.NODE_ENV = process.env.NODE_ENV || 'test';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const {
  PICKUP_CONFLICT_MIN_GAP_MS,
  assertNoPickupTimeConflict,
} = require('../src/policies/driverBookingConflictPolicy');

const ANCHOR = '2028-06-10T10:00:00+07:00';
const anchorMs = new Date(ANCHOR).getTime();

function pickupAtOffsetSeconds(offsetSec) {
  return new Date(anchorMs + offsetSec * 1000).toISOString();
}

function expectBlocked(offsetSec) {
  const row = [{ id: 900, scheduled_pickup_at: ANCHOR }];
  assert.throws(
    () => assertNoPickupTimeConflict(row, pickupAtOffsetSeconds(offsetSec)),
    (err) => err.errorCode === 'DRIVER_BOOKING_TIME_CONFLICT',
  );
}

function expectAllowed(offsetSec) {
  const row = [{ id: 900, scheduled_pickup_at: ANCHOR }];
  assert.doesNotThrow(
    () => assertNoPickupTimeConflict(row, pickupAtOffsetSeconds(offsetSec)),
  );
}

const OFFSETS = [
  { label: '59:59', sec: 3599, blocked: true },
  { label: '60:00', sec: 3600, blocked: true },
  { label: '60:01', sec: 3601, blocked: false },
  { label: '60:59', sec: 3659, blocked: false },
  { label: '61:00', sec: 3660, blocked: false },
];

for (const { label, sec, blocked } of OFFSETS) {
  test(`after anchor ${label} (${sec}s) is ${blocked ? 'blocked' : 'allowed'}`, () => {
    if (blocked) expectBlocked(sec);
    else expectAllowed(sec);
  });
  test(`before anchor ${label} (${sec}s) is ${blocked ? 'blocked' : 'allowed'}`, () => {
    if (blocked) expectBlocked(-sec);
    else expectAllowed(-sec);
  });
}

test('policy gap constant is one hour in milliseconds', () => {
  assert.equal(PICKUP_CONFLICT_MIN_GAP_MS, 60 * 60 * 1000);
});
