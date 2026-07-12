const BOOKING_STATUS = require('../constants/reservationStatus');

const REVIEW_ELIGIBLE_STATUSES = new Set([
  BOOKING_STATUS.SETTLEMENT_PENDING,
  BOOKING_STATUS.COMPLETED,
]);

function isBookingReviewEligible(booking) {
  return Boolean(
    booking
      && REVIEW_ELIGIBLE_STATUSES.has(booking.status)
      && booking.driver_id,
  );
}

module.exports = {
  REVIEW_ELIGIBLE_STATUSES,
  isBookingReviewEligible,
};
