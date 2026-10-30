// EMAIL only. IN_APP/FCM and domain events are deliberately unaffected.
const CUSTOMER_EMAIL_LIMIT = 3;
const CUSTOMER_EMAIL_TYPES = new Set(['BOOKING_CREATED', 'DRIVER_ASSIGNED', 'TRIP_ENDED', 'TRIP_COMPLETED', 'BOOKING_CANCELLED']);
function isTripEndEmail(notification) {
  const type=notification.type || notification.notificationType;
  let payload=notification.payload;
  if(typeof payload==='string'){try{payload=JSON.parse(payload)}catch{payload={}}}
  return type==='TRIP_ENDED' || (type==='TRIP_COMPLETED' && payload?.tripEndedDirectly===true);
}
function emailAudience(notification) {
  return notification.audience_role || notification.audienceRole
    || (notification.recipient_type === 'GUEST_BOOKING' ? 'CUSTOMER' : null)
    || notification.recipient_user_role
    || (notification.recipient_driver_id != null ? 'DRIVER' : null);
}
function emailPolicyError(notification) {
  const audience = emailAudience(notification);
  let bookingMetadata=notification.booking_metadata;
  if(typeof bookingMetadata==='string'){try{bookingMetadata=JSON.parse(bookingMetadata)}catch{bookingMetadata={}}}
  if(audience==='CUSTOMER' && (notification.type||notification.notificationType)==='BOOKING_CREATED' && bookingMetadata?.adminReceiptEmail?.approvedAt) return 'EMAIL_POLICY_LATE_CONFIRMATION_DISABLED';
  if (audience === 'DRIVER') return 'EMAIL_POLICY_DRIVER_DISABLED';
  if (audience === 'CUSTOMER' && (notification.type || notification.notificationType)==='TRIP_COMPLETED' && !isTripEndEmail(notification)) return 'EMAIL_POLICY_CUSTOMER_TYPE_DISABLED';
  if (audience === 'CUSTOMER' && !CUSTOMER_EMAIL_TYPES.has(notification.type || notification.notificationType)) {
    return 'EMAIL_POLICY_CUSTOMER_TYPE_DISABLED';
  }
  return null;
}
function customerEmailSlot(type) {
  return type === 'BOOKING_CREATED' ? 'RECEIPT' : type === 'DRIVER_ASSIGNED' ? 'ASSIGNMENT' : 'TERMINAL';
}
module.exports = { isTripEndEmail, CUSTOMER_EMAIL_LIMIT, CUSTOMER_EMAIL_TYPES, emailAudience, emailPolicyError, customerEmailSlot };
