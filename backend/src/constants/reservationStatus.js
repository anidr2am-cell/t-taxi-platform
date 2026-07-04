/**
 * constants/reservationStatus.js — Booking state machine states
 */
module.exports = {
  PENDING: 'PENDING',
  CONFIRMED: 'CONFIRMED',
  DRIVER_ASSIGNED: 'DRIVER_ASSIGNED',
  ON_ROUTE: 'ON_ROUTE',
  DRIVER_ARRIVED: 'DRIVER_ARRIVED',
  PICKED_UP: 'PICKED_UP',
  COMPLETED: 'COMPLETED',
  CANCELLED: 'CANCELLED',
  NO_SHOW: 'NO_SHOW',
};
