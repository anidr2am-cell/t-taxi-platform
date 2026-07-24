const BOOKING_STATUS = require('../constants/reservationStatus');
const {
  parseServiceDateTimeToMs,
  SERVICE_TIME_ZONE,
} = require('../utils/serviceDateTime.util');

const CUSTOMER_CANCEL_LEAD_MS = 2 * 60 * 60 * 1000;

const CUSTOMER_CANCELLABLE_STATUSES = new Set([
  BOOKING_STATUS.PENDING,
  BOOKING_STATUS.OPEN,
  BOOKING_STATUS.CONFIRMED,
  BOOKING_STATUS.DRIVER_ASSIGNED,
]);

const TRIP_STARTED_STATUSES = new Set([
  BOOKING_STATUS.ON_ROUTE,
  BOOKING_STATUS.DRIVER_ARRIVED,
  BOOKING_STATUS.PICKED_UP,
  BOOKING_STATUS.SETTLEMENT_PENDING,
]);

const CANCELLATION_BLOCKED_REASON = {
  ALREADY_CANCELLED: 'ALREADY_CANCELLED',
  COMPLETED: 'COMPLETED',
  NO_SHOW: 'NO_SHOW',
  TRIP_STARTED: 'TRIP_STARTED',
  WITHIN_TWO_HOURS: 'WITHIN_TWO_HOURS',
  INVALID_PICKUP_TIME: 'INVALID_PICKUP_TIME',
};

function formatCancellationDeadlineIso(deadlineMs) {
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

function cancellationDeadlineMs(scheduledPickupAt) {
  const pickupMs = parseServiceDateTimeToMs(scheduledPickupAt);
  if (pickupMs == null) return null;
  return pickupMs - CUSTOMER_CANCEL_LEAD_MS;
}

/**
 * Server-authoritative customer/guest cancellation eligibility.
 * Deadline is exclusive: canCancel only when nowMs < scheduledPickupAt - 2h.
 */
function evaluateCustomerCancellation({
  status,
  scheduledPickupAt,
  nowMs = Date.now(),
} = {}) {
  const deadlineMs = cancellationDeadlineMs(scheduledPickupAt);
  const cancellationDeadline = formatCancellationDeadlineIso(deadlineMs);

  if (status === BOOKING_STATUS.CANCELLED) {
    return {
      canCancel: false,
      cancellationDeadline,
      cancellationBlockedReason: CANCELLATION_BLOCKED_REASON.ALREADY_CANCELLED,
    };
  }
  if (status === BOOKING_STATUS.COMPLETED) {
    return {
      canCancel: false,
      cancellationDeadline,
      cancellationBlockedReason: CANCELLATION_BLOCKED_REASON.COMPLETED,
    };
  }
  if (status === BOOKING_STATUS.NO_SHOW) {
    return {
      canCancel: false,
      cancellationDeadline,
      cancellationBlockedReason: CANCELLATION_BLOCKED_REASON.NO_SHOW,
    };
  }
  if (TRIP_STARTED_STATUSES.has(status)) {
    return {
      canCancel: false,
      cancellationDeadline,
      cancellationBlockedReason: CANCELLATION_BLOCKED_REASON.TRIP_STARTED,
    };
  }
  if (!CUSTOMER_CANCELLABLE_STATUSES.has(status)) {
    return {
      canCancel: false,
      cancellationDeadline,
      cancellationBlockedReason: CANCELLATION_BLOCKED_REASON.TRIP_STARTED,
    };
  }
  if (deadlineMs == null) {
    return {
      canCancel: false,
      cancellationDeadline: null,
      cancellationBlockedReason: CANCELLATION_BLOCKED_REASON.INVALID_PICKUP_TIME,
    };
  }
  if (nowMs >= deadlineMs) {
    return {
      canCancel: false,
      cancellationDeadline,
      cancellationBlockedReason: CANCELLATION_BLOCKED_REASON.WITHIN_TWO_HOURS,
    };
  }

  return {
    canCancel: true,
    cancellationDeadline,
    cancellationBlockedReason: null,
  };
}

module.exports = {
  CUSTOMER_CANCEL_LEAD_MS,
  CUSTOMER_CANCELLABLE_STATUSES,
  TRIP_STARTED_STATUSES,
  CANCELLATION_BLOCKED_REASON,
  cancellationDeadlineMs,
  formatCancellationDeadlineIso,
  evaluateCustomerCancellation,
};
