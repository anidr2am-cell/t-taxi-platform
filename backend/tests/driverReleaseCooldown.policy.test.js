const test = require('node:test');
const assert = require('node:assert/strict');

const {
  RELEASE_COOLDOWN_MS,
  isBookingHiddenFromDriverByReleaseCooldown,
} = require('../src/policies/driverAssignmentRelease.policy');

const NOW = Date.parse('2026-07-22T12:00:00+07:00');
const DRIVER_A = 101;
const DRIVER_B = 202;

function releaseAt(offsetMs, driverId = DRIVER_A) {
  return {
    driverId,
    unassignedAt: new Date(NOW - offsetMs).toISOString(),
  };
}

test('driver A release hides booking from A immediately', () => {
  assert.equal(
    isBookingHiddenFromDriverByReleaseCooldown({
      currentDriverId: DRIVER_A,
      releaseRecords: [releaseAt(0)],
      nowMs: NOW,
    }),
    true,
  );
});

test('driver A release does not hide booking from driver B', () => {
  assert.equal(
    isBookingHiddenFromDriverByReleaseCooldown({
      currentDriverId: DRIVER_B,
      releaseRecords: [releaseAt(0)],
      nowMs: NOW,
    }),
    false,
  );
});

test('driver A still hidden at 29 minutes', () => {
  assert.equal(
    isBookingHiddenFromDriverByReleaseCooldown({
      currentDriverId: DRIVER_A,
      releaseRecords: [releaseAt(29 * 60 * 1000)],
      nowMs: NOW,
    }),
    true,
  );
});

test('driver A visible again at exactly 30 minutes', () => {
  assert.equal(
    isBookingHiddenFromDriverByReleaseCooldown({
      currentDriverId: DRIVER_A,
      releaseRecords: [releaseAt(RELEASE_COOLDOWN_MS)],
      nowMs: NOW,
    }),
    false,
  );
});

test('driver A visible at 31 minutes', () => {
  assert.equal(
    isBookingHiddenFromDriverByReleaseCooldown({
      currentDriverId: DRIVER_A,
      releaseRecords: [releaseAt(31 * 60 * 1000)],
      nowMs: NOW,
    }),
    false,
  );
});

test('new release after reassign starts a fresh cooldown for A', () => {
  assert.equal(
    isBookingHiddenFromDriverByReleaseCooldown({
      currentDriverId: DRIVER_A,
      releaseRecords: [
        releaseAt(40 * 60 * 1000),
        releaseAt(5 * 60 * 1000),
      ],
      nowMs: NOW,
    }),
    true,
  );
});

test('driver B release cools down only B', () => {
  const records = [releaseAt(5 * 60 * 1000, DRIVER_B)];
  assert.equal(
    isBookingHiddenFromDriverByReleaseCooldown({
      currentDriverId: DRIVER_A,
      releaseRecords: records,
      nowMs: NOW,
    }),
    false,
  );
  assert.equal(
    isBookingHiddenFromDriverByReleaseCooldown({
      currentDriverId: DRIVER_B,
      releaseRecords: records,
      nowMs: NOW,
    }),
    true,
  );
});

test('booking-level release without matching driver id never hides', () => {
  assert.equal(
    isBookingHiddenFromDriverByReleaseCooldown({
      currentDriverId: DRIVER_A,
      releaseRecords: [{ driverId: null, unassignedAt: new Date(NOW).toISOString() }],
      nowMs: NOW,
    }),
    false,
  );
});
