/**
 * events/index.js — In-process event bus (booking.created → notification)
 *
 * 대규모 확장 시 Redis / RabbitMQ로 교체 가능
 */
const { EventEmitter } = require('events');
const logger = require('../utils/logger');

const appEvents = new EventEmitter();

appEvents.on('error', (err) => {
  logger.error('EventEmitter error', { err });
});

// Event names (constants)
const EVENTS = {
  BOOKING_CREATED: 'booking.created',
  BOOKING_CONFIRMED: 'booking.confirmed',
  BOOKING_STATUS_CHANGED: 'booking.status_changed',
  DRIVER_ASSIGNED: 'driver.assigned',
  DRIVER_REASSIGNED: 'driver.reassigned',
  DRIVER_ARRIVED: 'driver.arrived',
  TRIP_PICKED_UP: 'trip.picked_up',
  TRIP_COMPLETED: 'trip.completed',
  BOOKING_CANCELLED: 'booking.cancelled',
  BOOKING_NO_SHOW: 'booking.no_show',
  COMMISSION_REQUIRED: 'commission.required',
  RECEIPT_SUBMITTED: 'receipt.submitted',
  RECEIPT_REJECTED: 'receipt.rejected',
  SETTLEMENT_APPROVED: 'settlement.approved',
  REVIEW_SUBMITTED: 'review.submitted',
  CHAT_MESSAGE_SENT: 'chat.message_sent',
  FLIGHT_DELAYED: 'flight.delayed',
  FLIGHT_CANCELLED: 'flight.cancelled',
  FLIGHT_LANDED: 'flight.landed',
};

module.exports = {
  appEvents,
  EVENTS,
};
