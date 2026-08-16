-- SELECT-only snapshot metadata for staging DB backup manifest.
-- Output is key=value lines with no secrets or customer PII.

SELECT CONCAT('DB_ENGINE_VERSION=', VERSION());

SELECT CONCAT(
  'TABLE_COUNT=',
  COUNT(*)
)
FROM information_schema.tables
WHERE table_schema = DATABASE()
  AND table_type = 'BASE TABLE';

SELECT CONCAT('ROW_COUNT_bookings=', COUNT(*)) FROM bookings;
SELECT CONCAT('ROW_COUNT_booking_driver_assignments=', COUNT(*)) FROM booking_driver_assignments;
SELECT CONCAT('ROW_COUNT_notifications=', COUNT(*)) FROM notifications;
SELECT CONCAT('ROW_COUNT_users=', COUNT(*)) FROM users;
SELECT CONCAT('ROW_COUNT_drivers=', COUNT(*)) FROM drivers;
SELECT CONCAT('ROW_COUNT_booking_contact_connections=', COUNT(*)) FROM booking_contact_connections;
SELECT CONCAT('ROW_COUNT_booking_idempotency_keys=', COUNT(*)) FROM booking_idempotency_keys;
SELECT CONCAT('ROW_COUNT_settlement_receipt_idempotency=', COUNT(*)) FROM settlement_receipt_idempotency;

SELECT CONCAT(
  'CONSTRAINT_uk_notifications_idempotency=',
  COUNT(*)
)
FROM information_schema.statistics
WHERE table_schema = DATABASE()
  AND table_name = 'notifications'
  AND index_name = 'uk_notifications_idempotency';

SELECT CONCAT(
  'CONSTRAINT_uk_bcc_one_active_per_booking=',
  COUNT(*)
)
FROM information_schema.statistics
WHERE table_schema = DATABASE()
  AND table_name = 'booking_contact_connections'
  AND index_name = 'uk_bcc_one_active_per_booking';

SELECT CONCAT(
  'CONSTRAINT_uk_booking_idempotency_key=',
  COUNT(*)
)
FROM information_schema.statistics
WHERE table_schema = DATABASE()
  AND table_name = 'booking_idempotency_keys'
  AND index_name = 'uk_booking_idempotency_key';

SELECT CONCAT(
  'CONSTRAINT_uk_settlement_receipt_idempotency_scope=',
  COUNT(*)
)
FROM information_schema.statistics
WHERE table_schema = DATABASE()
  AND table_name = 'settlement_receipt_idempotency'
  AND index_name = 'uk_settlement_receipt_idempotency_scope';

SELECT CONCAT(
  'LATEST_BOOKING_NUMBER=',
  COALESCE(MAX(booking_number), '')
)
FROM bookings;

SELECT CONCAT(
  'LATEST_BOOKING_CREATED_AT=',
  COALESCE(DATE_FORMAT(MAX(created_at), '%Y-%m-%d %H:%i:%s'), '')
)
FROM bookings;
