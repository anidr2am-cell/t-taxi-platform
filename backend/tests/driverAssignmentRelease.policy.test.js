const test = require('node:test');
const assert = require('node:assert/strict');

const {
  evaluateDriverAssignmentRelease,
  REASSIGNMENT_PRIORITY,
  RELEASE_BLOCKED_REASON,
  DRIVER_RELEASE_REASON,
} = require('../src/policies/driverAssignmentRelease.policy');

const PICKUP = '2026-07-25 15:00:00';
const pickupMs = Date.parse('2026-07-25T15:00:00+07:00');

test('pickup 7h before normal release → NORMAL', () => {
  const result = evaluateDriverAssignmentRelease({
    bookingStatus: 'DRIVER_ASSIGNED',
    scheduledPickupAt: PICKUP,
    reasonCode: DRIVER_RELEASE_REASON.SCHEDULE_CONFLICT,
    nowMs: pickupMs - 7 * 60 * 60 * 1000,
  });
  assert.equal(result.releaseAssignmentAvailable, true);
  assert.equal(result.reassignmentPriority, REASSIGNMENT_PRIORITY.NORMAL);
  assert.equal(result.releaseAssignmentEmergencyOnly, false);
});

test('pickup 5h before normal release → URGENT', () => {
  const result = evaluateDriverAssignmentRelease({
    bookingStatus: 'DRIVER_ASSIGNED',
    scheduledPickupAt: PICKUP,
    reasonCode: DRIVER_RELEASE_REASON.LOCATION_TOO_FAR,
    nowMs: pickupMs - 5 * 60 * 60 * 1000,
  });
  assert.equal(result.releaseAssignmentAvailable, true);
  assert.equal(result.reassignmentPriority, REASSIGNMENT_PRIORITY.URGENT);
});

test('pickup 2h+1s before normal release → allowed URGENT', () => {
  const result = evaluateDriverAssignmentRelease({
    bookingStatus: 'DRIVER_ASSIGNED',
    scheduledPickupAt: PICKUP,
    reasonCode: DRIVER_RELEASE_REASON.SCHEDULE_CONFLICT,
    nowMs: pickupMs - (2 * 60 * 60 * 1000 + 1000),
  });
  assert.equal(result.releaseAssignmentAvailable, true);
  assert.equal(result.reassignmentPriority, REASSIGNMENT_PRIORITY.URGENT);
});

test('exactly 2h before normal release → blocked', () => {
  const result = evaluateDriverAssignmentRelease({
    bookingStatus: 'DRIVER_ASSIGNED',
    scheduledPickupAt: PICKUP,
    reasonCode: DRIVER_RELEASE_REASON.SCHEDULE_CONFLICT,
    nowMs: pickupMs - 2 * 60 * 60 * 1000,
  });
  assert.equal(result.releaseAssignmentAvailable, false);
  assert.equal(
    result.assignmentReleaseBlockedReason,
    RELEASE_BLOCKED_REASON.WITHIN_TWO_HOURS,
  );
  assert.equal(result.releaseAssignmentEmergencyOnly, false);
});

test('1h before emergency reasons → CRITICAL release allowed', () => {
  for (const reasonCode of [
    DRIVER_RELEASE_REASON.VEHICLE_BREAKDOWN,
    DRIVER_RELEASE_REASON.ACCIDENT,
    DRIVER_RELEASE_REASON.DRIVER_ILLNESS,
    DRIVER_RELEASE_REASON.FAMILY_EMERGENCY,
  ]) {
    const result = evaluateDriverAssignmentRelease({
      bookingStatus: 'DRIVER_ASSIGNED',
      scheduledPickupAt: PICKUP,
      reasonCode,
      reasonDetail: 'detail',
      nowMs: pickupMs - 60 * 60 * 1000,
    });
    assert.equal(result.releaseAssignmentAvailable, true, reasonCode);
    assert.equal(result.reassignmentPriority, REASSIGNMENT_PRIORITY.CRITICAL);
    assert.equal(result.emergency, true);
  }
});

test('1h before non-emergency reasons are blocked', () => {
  for (const reasonCode of [
    DRIVER_RELEASE_REASON.SCHEDULE_CONFLICT,
    DRIVER_RELEASE_REASON.LOCATION_TOO_FAR,
    DRIVER_RELEASE_REASON.OTHER,
  ]) {
    const result = evaluateDriverAssignmentRelease({
      bookingStatus: 'DRIVER_ASSIGNED',
      scheduledPickupAt: PICKUP,
      reasonCode,
      reasonDetail: reasonCode === DRIVER_RELEASE_REASON.OTHER ? 'accident nearby' : null,
      nowMs: pickupMs - 60 * 60 * 1000,
    });
    assert.equal(result.releaseAssignmentAvailable, false, reasonCode);
    assert.equal(
      result.assignmentReleaseBlockedReason,
      RELEASE_BLOCKED_REASON.WITHIN_TWO_HOURS,
      reasonCode,
    );
  }
});

test('OTHER detail mentioning accident is not auto-classified emergency', () => {
  const result = evaluateDriverAssignmentRelease({
    bookingStatus: 'DRIVER_ASSIGNED',
    scheduledPickupAt: PICKUP,
    reasonCode: DRIVER_RELEASE_REASON.OTHER,
    reasonDetail: 'accident on the expressway',
    nowMs: pickupMs - 60 * 60 * 1000,
  });
  assert.equal(result.releaseAssignmentAvailable, false);
  assert.equal(result.emergency, false);
});

test('invalid reasonCode is rejected by allowlist', () => {
  const result = evaluateDriverAssignmentRelease({
    bookingStatus: 'DRIVER_ASSIGNED',
    scheduledPickupAt: PICKUP,
    reasonCode: 'FAKE_EMERGENCY',
    nowMs: pickupMs - 60 * 60 * 1000,
  });
  assert.equal(result.releaseAssignmentAvailable, false);
  assert.equal(
    result.assignmentReleaseBlockedReason,
    RELEASE_BLOCKED_REASON.INVALID_REASON,
  );
});

test('ON_ROUTE + ACCIDENT → driver direct release blocked', () => {
  const result = evaluateDriverAssignmentRelease({
    bookingStatus: 'ON_ROUTE',
    scheduledPickupAt: PICKUP,
    reasonCode: DRIVER_RELEASE_REASON.ACCIDENT,
    nowMs: pickupMs - 60 * 60 * 1000,
  });
  assert.equal(result.releaseAssignmentAvailable, false);
  assert.equal(
    result.assignmentReleaseBlockedReason,
    RELEASE_BLOCKED_REASON.TRIP_ALREADY_STARTED,
  );
});

test('trip started statuses are blocked', () => {
  for (const status of ['ON_ROUTE', 'DRIVER_ARRIVED', 'PICKED_UP', 'SETTLEMENT_PENDING']) {
    const result = evaluateDriverAssignmentRelease({
      bookingStatus: status,
      scheduledPickupAt: PICKUP,
      reasonCode: DRIVER_RELEASE_REASON.ACCIDENT,
      nowMs: pickupMs - 7 * 60 * 60 * 1000,
    });
    assert.equal(result.releaseAssignmentAvailable, false);
    assert.equal(
      result.assignmentReleaseBlockedReason,
      RELEASE_BLOCKED_REASON.TRIP_ALREADY_STARTED,
    );
  }
});

test('terminal statuses are blocked', () => {
  for (const status of ['COMPLETED', 'CANCELLED', 'NO_SHOW']) {
    const result = evaluateDriverAssignmentRelease({
      bookingStatus: status,
      scheduledPickupAt: PICKUP,
      reasonCode: DRIVER_RELEASE_REASON.ACCIDENT,
      nowMs: pickupMs - 7 * 60 * 60 * 1000,
    });
    assert.equal(result.releaseAssignmentAvailable, false);
    assert.equal(
      result.assignmentReleaseBlockedReason,
      RELEASE_BLOCKED_REASON.BOOKING_TERMINAL_STATUS,
    );
  }
});

test('invalid pickup and missing assignment are blocked', () => {
  assert.equal(
    evaluateDriverAssignmentRelease({
      bookingStatus: 'DRIVER_ASSIGNED',
      scheduledPickupAt: 'not-a-date',
      reasonCode: DRIVER_RELEASE_REASON.ACCIDENT,
    }).assignmentReleaseBlockedReason,
    RELEASE_BLOCKED_REASON.INVALID_PICKUP_TIME,
  );
  assert.equal(
    evaluateDriverAssignmentRelease({
      bookingStatus: 'DRIVER_ASSIGNED',
      scheduledPickupAt: PICKUP,
      hasActiveAssignment: false,
      reasonCode: DRIVER_RELEASE_REASON.ACCIDENT,
      nowMs: pickupMs - 7 * 60 * 60 * 1000,
    }).assignmentReleaseBlockedReason,
    RELEASE_BLOCKED_REASON.NO_ACTIVE_ASSIGNMENT,
  );
  assert.equal(
    evaluateDriverAssignmentRelease({
      bookingStatus: 'DRIVER_ASSIGNED',
      scheduledPickupAt: PICKUP,
      isAssignedDriver: false,
      reasonCode: DRIVER_RELEASE_REASON.ACCIDENT,
      nowMs: pickupMs - 7 * 60 * 60 * 1000,
    }).assignmentReleaseBlockedReason,
    RELEASE_BLOCKED_REASON.NOT_ASSIGNED_DRIVER,
  );
});

test('OTHER requires detail and CUSTOMER_REQUEST is rejected', () => {
  assert.equal(
    evaluateDriverAssignmentRelease({
      bookingStatus: 'DRIVER_ASSIGNED',
      scheduledPickupAt: PICKUP,
      reasonCode: DRIVER_RELEASE_REASON.OTHER,
      reasonDetail: '',
      nowMs: pickupMs - 7 * 60 * 60 * 1000,
    }).assignmentReleaseBlockedReason,
    RELEASE_BLOCKED_REASON.REASON_DETAIL_REQUIRED,
  );
  assert.equal(
    evaluateDriverAssignmentRelease({
      bookingStatus: 'DRIVER_ASSIGNED',
      scheduledPickupAt: PICKUP,
      reasonCode: 'CUSTOMER_REQUEST',
      nowMs: pickupMs - 7 * 60 * 60 * 1000,
    }).assignmentReleaseBlockedReason,
    RELEASE_BLOCKED_REASON.CUSTOMER_REQUEST_NOT_ALLOWED,
  );
});

test('capability snapshot marks emergency-only within 2h', () => {
  const result = evaluateDriverAssignmentRelease({
    bookingStatus: 'DRIVER_ASSIGNED',
    scheduledPickupAt: PICKUP,
    nowMs: pickupMs - 90 * 60 * 1000,
  });
  assert.equal(result.releaseAssignmentAvailable, false);
  assert.equal(result.releaseAssignmentEmergencyOnly, true);
  assert.equal(
    result.assignmentReleaseBlockedReason,
    RELEASE_BLOCKED_REASON.WITHIN_TWO_HOURS,
  );
});
