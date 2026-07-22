/**
 * Safe reason codes shown to a previously assigned driver when their
 * assignment is no longer active. Never invent booking existence for strangers.
 */
const ASSIGNMENT_ENDED_REASON = {
  CUSTOMER_CANCELLED: 'CUSTOMER_CANCELLED',
  ADMIN_CANCELLED: 'ADMIN_CANCELLED',
  DRIVER_RELEASED: 'DRIVER_RELEASED',
  REASSIGNED_TO_ANOTHER_DRIVER: 'REASSIGNED_TO_ANOTHER_DRIVER',
  TRIP_COMPLETED: 'TRIP_COMPLETED',
  NO_ACTIVE_ASSIGNMENT: 'NO_ACTIVE_ASSIGNMENT',
};

const DRIVER_RELEASE_ASSIGNMENT_REASON = 'DRIVER_RELEASED_ASSIGNMENT';

function resolveAssignmentEndedReason({
  bookingStatus,
  assignmentReason,
  hasOtherActiveAssignment = false,
} = {}) {
  if (hasOtherActiveAssignment) {
    return ASSIGNMENT_ENDED_REASON.REASSIGNED_TO_ANOTHER_DRIVER;
  }

  const reason = String(assignmentReason || '').trim().toUpperCase();
  if (reason === 'CUSTOMER_CANCELLED') {
    return ASSIGNMENT_ENDED_REASON.CUSTOMER_CANCELLED;
  }
  if (reason === 'ADMIN_CANCELLED') {
    return ASSIGNMENT_ENDED_REASON.ADMIN_CANCELLED;
  }
  if (reason === DRIVER_RELEASE_ASSIGNMENT_REASON) {
    return ASSIGNMENT_ENDED_REASON.DRIVER_RELEASED;
  }

  const status = String(bookingStatus || '').trim().toUpperCase();
  if (status === 'CANCELLED') {
    // Prefer explicit assignment reasons above; fall back to admin cancel label
    // when history is incomplete so we never claim customer cancel incorrectly.
    return ASSIGNMENT_ENDED_REASON.ADMIN_CANCELLED;
  }
  if (status === 'COMPLETED' || status === 'NO_SHOW') {
    return ASSIGNMENT_ENDED_REASON.TRIP_COMPLETED;
  }
  if (['OPEN', 'PENDING', 'CONFIRMED'].includes(status)) {
    return ASSIGNMENT_ENDED_REASON.DRIVER_RELEASED;
  }

  return ASSIGNMENT_ENDED_REASON.NO_ACTIVE_ASSIGNMENT;
}

function safeMessageForEndedReason(reasonCode) {
  switch (reasonCode) {
    case ASSIGNMENT_ENDED_REASON.CUSTOMER_CANCELLED:
      return 'The customer cancelled the booking and your assignment was released.';
    case ASSIGNMENT_ENDED_REASON.ADMIN_CANCELLED:
      return 'An admin cancelled the booking and your assignment was released.';
    case ASSIGNMENT_ENDED_REASON.DRIVER_RELEASED:
      return 'Assignment release completed. The booking is open for other drivers.';
    case ASSIGNMENT_ENDED_REASON.REASSIGNED_TO_ANOTHER_DRIVER:
      return 'This booking was assigned to another driver.';
    case ASSIGNMENT_ENDED_REASON.TRIP_COMPLETED:
      return 'This trip is already completed.';
    default:
      return 'You no longer have an active assignment for this booking.';
  }
}

module.exports = {
  ASSIGNMENT_ENDED_REASON,
  DRIVER_RELEASE_ASSIGNMENT_REASON,
  resolveAssignmentEndedReason,
  safeMessageForEndedReason,
};
