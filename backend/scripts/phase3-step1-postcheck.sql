SELECT COLUMN_NAME, GENERATION_EXPRESSION, EXTRA
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME = 'booking_contact_connections'
  AND COLUMN_NAME = 'active_connection_guard';

SELECT INDEX_NAME, NON_UNIQUE, COLUMN_NAME
FROM information_schema.STATISTICS
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME = 'booking_contact_connections'
  AND INDEX_NAME = 'uk_bcc_one_active_per_booking';

SELECT IFNULL(MAX(active_count), 0) AS max_active_per_booking
FROM (
  SELECT booking_id, COUNT(*) AS active_count
  FROM booking_contact_connections
  WHERE status IN ('PENDING','CONFIRM_REQUESTED','VERIFIED')
  GROUP BY booking_id
) t;
