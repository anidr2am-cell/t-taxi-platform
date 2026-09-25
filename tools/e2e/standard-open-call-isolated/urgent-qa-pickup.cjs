'use strict';

/** URGENT bookings: pickup must be in the future and within 2 hours (booking.validator). */
function urgentPickupIso(minutesFromNow = 75) {
  const clamped = Math.min(Math.max(Number(minutesFromNow) || 75, 5), 115);
  return new Date(Date.now() + clamped * 60 * 1000).toISOString();
}

module.exports = { urgentPickupIso };
