/**
 * Notification domain events are processed via outbox_events (OutboxProcessor).
 * EventEmitter remains only for settlement (trip.completed -> commission obligation).
 */
function registerNotificationHandlers() {
  // Intentionally empty — see outbox write → commit → processor dispatch flow.
}

module.exports = { registerNotificationHandlers };
