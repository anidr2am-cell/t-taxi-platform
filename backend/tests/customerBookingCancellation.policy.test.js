const { test } = require('node:test');
const assert = require('node:assert/strict');

const BOOKING_STATUS = require('../src/constants/reservationStatus');
const {
  evaluateCustomerCancellation,
  CANCELLATION_BLOCKED_REASON,
} = require('../src/policies/customerBookingCancellation.policy');

const PICKUP = '2026-07-25 15:00:00';
// Deadline exclusive: 2026-07-25 13:00:00 +07:00
const DEADLINE_MS = Date.parse('2026-07-25T13:00:00+07:00');
const ONE_SEC = 1000;

test('after driver release OPEN booking 3h before pickup can still cancel', () => {
  const result = evaluateCustomerCancellation({
    status: BOOKING_STATUS.OPEN,
    scheduledPickupAt: PICKUP,
    nowMs: DEADLINE_MS - (60 * 60 * 1000),
  });
  assert.equal(result.canCancel, true);
});

test('after driver release OPEN booking exactly 2h before pickup cannot cancel', () => {
  const result = evaluateCustomerCancellation({
    status: BOOKING_STATUS.OPEN,
    scheduledPickupAt: PICKUP,
    nowMs: DEADLINE_MS,
  });
  assert.equal(result.canCancel, false);
  assert.equal(
    result.cancellationBlockedReason,
    CANCELLATION_BLOCKED_REASON.WITHIN_TWO_HOURS,
  );
});

test('driver assigned 3h before pickup can cancel', () => {
  const result = evaluateCustomerCancellation({
    status: BOOKING_STATUS.DRIVER_ASSIGNED,
    scheduledPickupAt: PICKUP,
    nowMs: DEADLINE_MS - (60 * 60 * 1000),
  });
  assert.equal(result.canCancel, true);
});

test('driver accepted 2h+1s before pickup can cancel', () => {
  const result = evaluateCustomerCancellation({
    status: BOOKING_STATUS.DRIVER_ASSIGNED,
    scheduledPickupAt: PICKUP,
    nowMs: DEADLINE_MS - ONE_SEC,
  });
  assert.equal(result.canCancel, true);
});

test('exactly 2h before pickup cannot cancel', () => {
  const result = evaluateCustomerCancellation({
    status: BOOKING_STATUS.DRIVER_ASSIGNED,
    scheduledPickupAt: PICKUP,
    nowMs: DEADLINE_MS,
  });
  assert.equal(result.canCancel, false);
  assert.equal(
    result.cancellationBlockedReason,
    CANCELLATION_BLOCKED_REASON.WITHIN_TWO_HOURS,
  );
});

test('1h59m before pickup cannot cancel', () => {
  const result = evaluateCustomerCancellation({
    status: BOOKING_STATUS.DRIVER_ASSIGNED,
    scheduledPickupAt: PICKUP,
    nowMs: DEADLINE_MS + (60 * 1000),
  });
  assert.equal(result.canCancel, false);
  assert.equal(
    result.cancellationBlockedReason,
    CANCELLATION_BLOCKED_REASON.WITHIN_TWO_HOURS,
  );
});

test('trip started statuses cannot cancel', () => {
  for (const status of [
    BOOKING_STATUS.ON_ROUTE,
    BOOKING_STATUS.DRIVER_ARRIVED,
    BOOKING_STATUS.PICKED_UP,
    BOOKING_STATUS.SETTLEMENT_PENDING,
  ]) {
    const result = evaluateCustomerCancellation({
      status,
      scheduledPickupAt: PICKUP,
      nowMs: DEADLINE_MS - (3 * 60 * 60 * 1000),
    });
    assert.equal(result.canCancel, false, status);
    assert.equal(
      result.cancellationBlockedReason,
      CANCELLATION_BLOCKED_REASON.TRIP_STARTED,
      status,
    );
  }
});

test('terminal statuses cannot cancel', () => {
  assert.equal(
    evaluateCustomerCancellation({
      status: BOOKING_STATUS.COMPLETED,
      scheduledPickupAt: PICKUP,
      nowMs: DEADLINE_MS - ONE_SEC,
    }).cancellationBlockedReason,
    CANCELLATION_BLOCKED_REASON.COMPLETED,
  );
  assert.equal(
    evaluateCustomerCancellation({
      status: BOOKING_STATUS.CANCELLED,
      scheduledPickupAt: PICKUP,
      nowMs: DEADLINE_MS - ONE_SEC,
    }).cancellationBlockedReason,
    CANCELLATION_BLOCKED_REASON.ALREADY_CANCELLED,
  );
  assert.equal(
    evaluateCustomerCancellation({
      status: BOOKING_STATUS.NO_SHOW,
      scheduledPickupAt: PICKUP,
      nowMs: DEADLINE_MS - ONE_SEC,
    }).cancellationBlockedReason,
    CANCELLATION_BLOCKED_REASON.NO_SHOW,
  );
});

test('invalid pickup time cannot cancel', () => {
  const result = evaluateCustomerCancellation({
    status: BOOKING_STATUS.OPEN,
    scheduledPickupAt: 'not-a-date',
    nowMs: DEADLINE_MS - ONE_SEC,
  });
  assert.equal(result.canCancel, false);
  assert.equal(
    result.cancellationBlockedReason,
    CANCELLATION_BLOCKED_REASON.INVALID_PICKUP_TIME,
  );
});

test('driver assignment alone does not block cancellation', () => {
  const result = evaluateCustomerCancellation({
    status: BOOKING_STATUS.DRIVER_ASSIGNED,
    scheduledPickupAt: PICKUP,
    nowMs: DEADLINE_MS - (5 * 60 * 60 * 1000),
  });
  assert.equal(result.canCancel, true);
});
