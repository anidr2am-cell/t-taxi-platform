// EMAIL only. IN_APP/FCM and domain events are deliberately unaffected.
const CUSTOMER_EMAIL_TYPES = new Set(['BOOKING_CREATED', 'TRIP_ENDED', 'BOOKING_CANCELLED']);
function emailAudience(notification) {
  return notification.audience_role || notification.audienceRole
    || (notification.recipient_type === 'GUEST_BOOKING' ? 'CUSTOMER' : null)
    || notification.recipient_user_role
    || (notification.recipient_driver_id != null ? 'DRIVER' : null);
}
function emailPolicyError(notification) {
  const audience = emailAudience(notification);
  if (audience === 'DRIVER') return 'EMAIL_POLICY_DRIVER_DISABLED';
  if (audience === 'CUSTOMER' && !CUSTOMER_EMAIL_TYPES.has(notification.type || notification.notificationType)) {
    return 'EMAIL_POLICY_CUSTOMER_TYPE_DISABLED';
  }
  return null;
}
function customerEmailSlot(type) {
  return type === 'BOOKING_CREATED' ? 'RECEIPT' : 'TERMINAL';
}
module.exports = { CUSTOMER_EMAIL_TYPES, emailAudience, emailPolicyError, customerEmailSlot };
