SELECT
  b.booking_number,
  b.status,
  b.contact_status,
  JSON_EXTRACT(b.metadata, '$.contactDispatchCompleted') AS contact_dispatch_completed,
  JSON_EXTRACT(b.metadata, '$.contactDispatchDelivered') AS contact_dispatch_delivered
FROM bookings b
WHERE b.booking_number = '@BOOKING_NUMBER@';

SELECT COUNT(*) AS driver_call_notification_count
FROM notifications n
JOIN bookings b ON b.id = n.booking_id
WHERE b.booking_number = '@BOOKING_NUMBER@'
  AND n.type = 'DRIVER_CALL_AVAILABLE'
  AND n.deleted_at IS NULL;

SELECT
  n.id,
  n.recipient_driver_id,
  n.idempotency_key,
  n.type,
  n.created_at
FROM notifications n
JOIN bookings b ON b.id = n.booking_id
WHERE b.booking_number = '@BOOKING_NUMBER@'
  AND n.deleted_at IS NULL
ORDER BY n.id;

SELECT COUNT(*) AS duplicate_idempotency_key_count
FROM (
  SELECT n.idempotency_key
  FROM notifications n
  JOIN bookings b ON b.id = n.booking_id
  WHERE b.booking_number = '@BOOKING_NUMBER@'
    AND n.deleted_at IS NULL
    AND n.idempotency_key IS NOT NULL
  GROUP BY n.idempotency_key
  HAVING COUNT(*) > 1
) dup;

SELECT COUNT(*) AS active_assignment_count
FROM booking_driver_assignments bda
JOIN bookings b ON b.id = bda.booking_id
WHERE b.booking_number = '@BOOKING_NUMBER@'
  AND bda.is_active = 1;

SELECT
  n.recipient_driver_id,
  n.idempotency_key,
  COUNT(*) AS notification_row_count
FROM notifications n
JOIN bookings b ON b.id = n.booking_id
WHERE b.booking_number = '@BOOKING_NUMBER@'
  AND n.deleted_at IS NULL
  AND n.type = 'DRIVER_CALL_AVAILABLE'
GROUP BY n.recipient_driver_id, n.idempotency_key
ORDER BY n.recipient_driver_id, n.idempotency_key;
