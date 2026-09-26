const CONTACT_STATUS = require('../constants/contactStatus');
const BOOKING_STATUS = require('../constants/reservationStatus');

const CONTACT_DISPATCH_STATE = {
  NOT_APPLICABLE: 'NOT_APPLICABLE',
  WAITING_CONTACT: 'WAITING_CONTACT',
  DISPATCH_PENDING: 'DISPATCH_PENDING',
  DELIVERY_RETRY_NEEDED: 'DELIVERY_RETRY_NEEDED',
  DELIVERY_ATTEMPTED: 'DELIVERY_ATTEMPTED',
  NOT_OPEN: 'NOT_OPEN',
};

const CONTACT_DISPATCH_MODE = {
  STANDARD: 'STANDARD',
  URGENT: 'URGENT',
};

function parseBookingMetadata(metadata) {
  if (!metadata) return {};
  if (typeof metadata === 'object') return metadata;
  try {
    const parsed = JSON.parse(metadata);
    return parsed && typeof parsed === 'object' ? parsed : {};
  } catch (_) {
    return {};
  }
}

function readDispatchMarkers(metadata) {
  const parsed = parseBookingMetadata(metadata);
  return {
    persisted: parsed.contactDispatchCompleted === true,
    deliveryAttempted: parsed.contactDispatchDelivered === true,
  };
}

function isUrgentBooking(input = {}) {
  const value = input.isUrgentRequest ?? input.is_urgent_request;
  return value === true || value === 1 || value === '1';
}

function hasContactFlowEvidence(input = {}) {
  if (input.transitionedToVerified === true) return true;
  if (input.hasConnectionRow === true) return true;
  const requestedAt = input.contactRequestedAt ?? input.contact_requested_at;
  return requestedAt != null && String(requestedAt).trim() !== '';
}

function normalizeContactStatus(input = {}) {
  return input.contactStatus ?? input.contact_status ?? CONTACT_STATUS.VERIFIED;
}

function normalizeBookingStatus(input = {}) {
  return input.bookingStatus ?? input.status ?? null;
}

function isContactDispatchRetryable(input = {}) {
  const contactStatus = normalizeContactStatus(input);
  const bookingStatus = normalizeBookingStatus(input);
  const markers = input.markers ?? readDispatchMarkers(input.metadata);
  if (bookingStatus !== BOOKING_STATUS.OPEN) return false;
  if (contactStatus !== CONTACT_STATUS.VERIFIED) return false;
  if (markers.deliveryAttempted) return false;
  if (markers.persisted) return true;
  return hasContactFlowEvidence(input);
}

function canVerifyContact(input = {}) {
  return normalizeBookingStatus(input) === BOOKING_STATUS.OPEN
    && normalizeContactStatus(input) === CONTACT_STATUS.CONFIRM_REQUESTED;
}

function deriveContactDispatch(input = {}) {
  const contactStatus = normalizeContactStatus(input);
  const bookingStatus = normalizeBookingStatus(input);
  const markers = readDispatchMarkers(input.metadata);
  const isOpen = bookingStatus === BOOKING_STATUS.OPEN;
  const contactFlow = hasContactFlowEvidence(input)
    || markers.persisted
    || markers.deliveryAttempted;
  const mode = isUrgentBooking(input)
    ? CONTACT_DISPATCH_MODE.URGENT
    : CONTACT_DISPATCH_MODE.STANDARD;

  let state;
  if (!isOpen && contactFlow) {
    state = CONTACT_DISPATCH_STATE.NOT_OPEN;
  } else if (
    contactStatus === CONTACT_STATUS.PENDING
    || contactStatus === CONTACT_STATUS.CONFIRM_REQUESTED
  ) {
    state = CONTACT_DISPATCH_STATE.WAITING_CONTACT;
  } else if (markers.deliveryAttempted) {
    state = CONTACT_DISPATCH_STATE.DELIVERY_ATTEMPTED;
  } else if (markers.persisted && isOpen) {
    state = CONTACT_DISPATCH_STATE.DELIVERY_RETRY_NEEDED;
  } else if (
    contactStatus === CONTACT_STATUS.VERIFIED
    && isOpen
    && !markers.persisted
    && hasContactFlowEvidence(input)
  ) {
    state = CONTACT_DISPATCH_STATE.DISPATCH_PENDING;
  } else {
    state = CONTACT_DISPATCH_STATE.NOT_APPLICABLE;
  }

  return {
    state,
    persisted: markers.persisted,
    deliveryAttempted: markers.deliveryAttempted,
    retryable: isContactDispatchRetryable({
      ...input,
      contactStatus,
      bookingStatus,
      markers,
    }),
    mode,
  };
}

function contactDispatchInputFromBooking(booking = {}, extras = {}) {
  return {
    contactStatus: booking.contact_status ?? booking.contactStatus,
    status: booking.status ?? booking.bookingStatus,
    metadata: booking.metadata,
    contactRequestedAt: booking.contact_requested_at ?? booking.contactRequestedAt,
    is_urgent_request: booking.is_urgent_request ?? booking.isUrgentRequest,
    hasConnectionRow: extras.hasConnectionRow === true,
    transitionedToVerified: extras.transitionedToVerified === true,
  };
}

module.exports = {
  CONTACT_DISPATCH_STATE,
  CONTACT_DISPATCH_MODE,
  parseBookingMetadata,
  readDispatchMarkers,
  isUrgentBooking,
  hasContactFlowEvidence,
  isContactDispatchRetryable,
  canVerifyContact,
  deriveContactDispatch,
  contactDispatchInputFromBooking,
};
