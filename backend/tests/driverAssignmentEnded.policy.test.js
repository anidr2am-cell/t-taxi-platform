const test = require('node:test');
const assert = require('node:assert/strict');

const {
  ASSIGNMENT_ENDED_REASON,
  resolveAssignmentEndedReason,
} = require('../src/policies/driverAssignmentEnded.policy');

test('customer cancel reason maps correctly', () => {
  assert.equal(
    resolveAssignmentEndedReason({
      bookingStatus: 'CANCELLED',
      assignmentReason: 'CUSTOMER_CANCELLED',
    }),
    ASSIGNMENT_ENDED_REASON.CUSTOMER_CANCELLED,
  );
});

test('admin cancel reason maps correctly', () => {
  assert.equal(
    resolveAssignmentEndedReason({
      bookingStatus: 'CANCELLED',
      assignmentReason: 'ADMIN_CANCELLED',
    }),
    ASSIGNMENT_ENDED_REASON.ADMIN_CANCELLED,
  );
});

test('driver release reason maps correctly', () => {
  assert.equal(
    resolveAssignmentEndedReason({
      bookingStatus: 'OPEN',
      assignmentReason: 'DRIVER_RELEASED_ASSIGNMENT',
    }),
    ASSIGNMENT_ENDED_REASON.DRIVER_RELEASED,
  );
});

test('other active assignment wins as reassigned', () => {
  assert.equal(
    resolveAssignmentEndedReason({
      bookingStatus: 'DRIVER_ASSIGNED',
      assignmentReason: 'CUSTOMER_CANCELLED',
      hasOtherActiveAssignment: true,
    }),
    ASSIGNMENT_ENDED_REASON.REASSIGNED_TO_ANOTHER_DRIVER,
  );
});

test('cancelled without explicit reason falls back to admin cancelled', () => {
  assert.equal(
    resolveAssignmentEndedReason({
      bookingStatus: 'CANCELLED',
      assignmentReason: null,
    }),
    ASSIGNMENT_ENDED_REASON.ADMIN_CANCELLED,
  );
});
