const BOOKING_STATUS = require('../constants/reservationStatus');
const {
  parseServiceDateTimeToMs,
  SERVICE_TIME_ZONE,
} = require('../utils/serviceDateTime.util');

const TWO_HOURS_MS = 2 * 60 * 60 * 1000;
const SIX_HOURS_MS = 6 * 60 * 60 * 1000;
const RELEASE_COOLDOWN_MS = 30 * 60 * 1000;

const DRIVER_RELEASE_REASON = {
  VEHICLE_BREAKDOWN: 'VEHICLE_BREAKDOWN',
  ACCIDENT: 'ACCIDENT',
  DRIVER_ILLNESS: 'DRIVER_ILLNESS',
  FAMILY_EMERGENCY: 'FAMILY_EMERGENCY',
  SCHEDULE_CONFLICT: 'SCHEDULE_CONFLICT',
  LOCATION_TOO_FAR: 'LOCATION_TOO_FAR',
  OTHER: 'OTHER',
};

const EMERGENCY_RELEASE_REASONS = new Set([
  DRIVER_RELEASE_REASON.VEHICLE_BREAKDOWN,
  DRIVER_RELEASE_REASON.ACCIDENT,
  DRIVER_RELEASE_REASON.DRIVER_ILLNESS,
  DRIVER_RELEASE_REASON.FAMILY_EMERGENCY,
]);

const REASSIGNMENT_PRIORITY = {
  NORMAL: 'NORMAL',
  URGENT: 'URGENT',
  CRITICAL: 'CRITICAL',
};

const RELEASE_BLOCKED_REASON = {
  NOT_ASSIGNED_DRIVER: 'NOT_ASSIGNED_DRIVER',
  NO_ACTIVE_ASSIGNMENT: 'NO_ACTIVE_ASSIGNMENT',
  TRIP_ALREADY_STARTED: 'TRIP_ALREADY_STARTED',
  WITHIN_TWO_HOURS: 'WITHIN_TWO_HOURS',
  BOOKING_TERMINAL_STATUS: 'BOOKING_TERMINAL_STATUS',
  INVALID_PICKUP_TIME: 'INVALID_PICKUP_TIME',
  INVALID_REASON: 'INVALID_REASON',
  REASON_DETAIL_REQUIRED: 'REASON_DETAIL_REQUIRED',
  CUSTOMER_REQUEST_NOT_ALLOWED: 'CUSTOMER_REQUEST_NOT_ALLOWED',
};

const TERMINAL_BOOKING_STATUSES = new Set([
  BOOKING_STATUS.CANCELLED,
  BOOKING_STATUS.COMPLETED,
  BOOKING_STATUS.NO_SHOW,
]);

const TRIP_STARTED_STATUSES = new Set([
  BOOKING_STATUS.ON_ROUTE,
  BOOKING_STATUS.DRIVER_ARRIVED,
  BOOKING_STATUS.PICKED_UP,
  BOOKING_STATUS.SETTLEMENT_PENDING,
]);

const ASSIGNMENT_RELEASE_MARKER = 'DRIVER_RELEASED_ASSIGNMENT';

function formatDeadlineIso(deadlineMs) {
  if (deadlineMs == null || !Number.isFinite(deadlineMs)) return null;
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone: SERVICE_TIME_ZONE,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hourCycle: 'h23',
    hour12: false,
  }).formatToParts(new Date(deadlineMs));
  const part = (type) => parts.find((item) => item.type === type)?.value;
  const hour = part('hour') === '24' ? '00' : part('hour');
  return `${part('year')}-${part('month')}-${part('day')}T${hour}:${part('minute')}:${part('second')}+07:00`;
}

function remainingMsUntilPickup(scheduledPickupAt, nowMs = Date.now()) {
  const pickupMs = parseServiceDateTimeToMs(scheduledPickupAt);
  if (pickupMs == null) return null;
  return pickupMs - nowMs;
}

function priorityForRemainingMs(remainingMs) {
  if (remainingMs == null || !Number.isFinite(remainingMs)) {
    return REASSIGNMENT_PRIORITY.NORMAL;
  }
  if (remainingMs <= TWO_HOURS_MS) return REASSIGNMENT_PRIORITY.CRITICAL;
  if (remainingMs < SIX_HOURS_MS) return REASSIGNMENT_PRIORITY.URGENT;
  return REASSIGNMENT_PRIORITY.NORMAL;
}

function isEmergencyReason(reasonCode) {
  return EMERGENCY_RELEASE_REASONS.has(String(reasonCode || '').trim());
}

/**
 * Per-driver release cooldown: hide a booking from the *same* driver only.
 * Exact 30-minute boundary is exclusive (unassignedAt + 30m → visible again).
 * Other drivers are never hidden by another driver's release.
 */
function isBookingHiddenFromDriverByReleaseCooldown({
  currentDriverId,
  releaseRecords = [],
  nowMs = Date.now(),
  cooldownMs = RELEASE_COOLDOWN_MS,
} = {}) {
  const driverId = Number(currentDriverId);
  if (!Number.isFinite(driverId) || driverId <= 0) return false;

  return releaseRecords.some((record) => {
    if (Number(record?.driverId) !== driverId) return false;
    const unassignedMs = parseServiceDateTimeToMs(record?.unassignedAt);
    if (unassignedMs == null || !Number.isFinite(unassignedMs)) return false;
    // Hide while age < cooldown; at exactly cooldownMs the booking is visible again.
    return nowMs - unassignedMs < cooldownMs;
  });
}

function normalizeReasonCode(reasonCode) {
  const value = String(reasonCode || '').trim().toUpperCase();
  if (value === 'CUSTOMER_REQUEST') {
    return {
      ok: false,
      blockedReason: RELEASE_BLOCKED_REASON.CUSTOMER_REQUEST_NOT_ALLOWED,
    };
  }
  if (!Object.values(DRIVER_RELEASE_REASON).includes(value)) {
    return { ok: false, blockedReason: RELEASE_BLOCKED_REASON.INVALID_REASON };
  }
  return { ok: true, reasonCode: value };
}

function normalizeReasonDetail(reasonCode, reasonDetail) {
  const detail = String(reasonDetail || '').trim();
  if (reasonCode === DRIVER_RELEASE_REASON.OTHER && detail.length < 3) {
    return {
      ok: false,
      blockedReason: RELEASE_BLOCKED_REASON.REASON_DETAIL_REQUIRED,
    };
  }
  return { ok: true, reasonDetail: detail.length ? detail : null };
}

/**
 * Server-authoritative driver assignment release eligibility.
 * Normal release requires now < scheduledPickupAt - 2h (exclusive deadline).
 * Within 2 hours only emergency reason codes may release immediately (CRITICAL).
 */
function evaluateDriverAssignmentRelease({
  bookingStatus,
  scheduledPickupAt,
  hasActiveAssignment = true,
  isAssignedDriver = true,
  reasonCode = null,
  reasonDetail = null,
  nowMs = Date.now(),
} = {}) {
  const pickupMs = parseServiceDateTimeToMs(scheduledPickupAt);
  const deadlineMs = pickupMs == null ? null : pickupMs - TWO_HOURS_MS;
  const assignmentReleaseDeadline = formatDeadlineIso(deadlineMs);
  const remainingMs = pickupMs == null ? null : pickupMs - nowMs;
  const basePriority = priorityForRemainingMs(remainingMs);

  const blocked = (assignmentReleaseBlockedReason, extras = {}) => ({
    releaseAssignmentAvailable: false,
    releaseAssignmentEmergencyOnly: false,
    assignmentReleaseDeadline,
    assignmentReleaseBlockedReason,
    reassignmentPriority: extras.reassignmentPriority ?? basePriority,
    remainingMs,
    emergency: false,
    reasonCode: extras.reasonCode ?? null,
    reasonDetail: extras.reasonDetail ?? null,
  });

  if (TERMINAL_BOOKING_STATUSES.has(bookingStatus)) {
    return blocked(RELEASE_BLOCKED_REASON.BOOKING_TERMINAL_STATUS);
  }
  if (TRIP_STARTED_STATUSES.has(bookingStatus)) {
    return blocked(RELEASE_BLOCKED_REASON.TRIP_ALREADY_STARTED);
  }
  if (bookingStatus !== BOOKING_STATUS.DRIVER_ASSIGNED) {
    return blocked(RELEASE_BLOCKED_REASON.TRIP_ALREADY_STARTED);
  }
  if (!hasActiveAssignment) {
    return blocked(RELEASE_BLOCKED_REASON.NO_ACTIVE_ASSIGNMENT);
  }
  if (!isAssignedDriver) {
    return blocked(RELEASE_BLOCKED_REASON.NOT_ASSIGNED_DRIVER);
  }
  if (deadlineMs == null || remainingMs == null) {
    return blocked(RELEASE_BLOCKED_REASON.INVALID_PICKUP_TIME);
  }

  const withinTwoHours = nowMs >= deadlineMs;
  const emergencyOnly = withinTwoHours;

  if (reasonCode == null) {
    return {
      releaseAssignmentAvailable: !emergencyOnly,
      releaseAssignmentEmergencyOnly: emergencyOnly,
      assignmentReleaseDeadline,
      assignmentReleaseBlockedReason: emergencyOnly
        ? RELEASE_BLOCKED_REASON.WITHIN_TWO_HOURS
        : null,
      reassignmentPriority: basePriority,
      remainingMs,
      emergency: false,
      reasonCode: null,
      reasonDetail: null,
    };
  }

  const normalizedReason = normalizeReasonCode(reasonCode);
  if (!normalizedReason.ok) {
    return blocked(normalizedReason.blockedReason);
  }
  const normalizedDetail = normalizeReasonDetail(
    normalizedReason.reasonCode,
    reasonDetail,
  );
  if (!normalizedDetail.ok) {
    return blocked(normalizedDetail.blockedReason, {
      reasonCode: normalizedReason.reasonCode,
    });
  }

  const emergency = isEmergencyReason(normalizedReason.reasonCode);
  if (emergencyOnly && !emergency) {
    return blocked(RELEASE_BLOCKED_REASON.WITHIN_TWO_HOURS, {
      reasonCode: normalizedReason.reasonCode,
      reasonDetail: normalizedDetail.reasonDetail,
      reassignmentPriority: REASSIGNMENT_PRIORITY.CRITICAL,
    });
  }

  const reassignmentPriority = emergencyOnly
    ? REASSIGNMENT_PRIORITY.CRITICAL
    : basePriority;

  return {
    releaseAssignmentAvailable: true,
    releaseAssignmentEmergencyOnly: emergencyOnly,
    assignmentReleaseDeadline,
    assignmentReleaseBlockedReason: null,
    reassignmentPriority,
    remainingMs,
    emergency: emergencyOnly || emergency,
    reasonCode: normalizedReason.reasonCode,
    reasonDetail: normalizedDetail.reasonDetail,
  };
}

module.exports = {
  TWO_HOURS_MS,
  SIX_HOURS_MS,
  RELEASE_COOLDOWN_MS,
  DRIVER_RELEASE_REASON,
  EMERGENCY_RELEASE_REASONS,
  REASSIGNMENT_PRIORITY,
  RELEASE_BLOCKED_REASON,
  ASSIGNMENT_RELEASE_MARKER,
  remainingMsUntilPickup,
  priorityForRemainingMs,
  isEmergencyReason,
  isBookingHiddenFromDriverByReleaseCooldown,
  evaluateDriverAssignmentRelease,
};
