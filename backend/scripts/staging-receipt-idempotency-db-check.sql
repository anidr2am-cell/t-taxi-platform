SELECT b.booking_number,
       b.commission_receipt_file_id,
       COUNT(DISTINCT CASE WHEN f.deleted_at IS NULL THEN f.id END) AS active_receipt_files,
       SUM(CASE WHEN al.activity_type = 'COMMISSION_RECEIPT_UPLOADED' THEN 1 ELSE 0 END) AS receipt_activity_count,
       SUM(CASE WHEN oe.event_type = 'RECEIPT_SUBMITTED' THEN 1 ELSE 0 END) AS receipt_outbox_count
FROM bookings b
LEFT JOIN files f
  ON f.entity_id = b.id
 AND f.entity_type = 'COMMISSION_RECEIPT'
LEFT JOIN booking_activity_logs al
  ON al.booking_id = b.id
 AND al.activity_type = 'COMMISSION_RECEIPT_UPLOADED'
LEFT JOIN outbox_events oe
  ON oe.aggregate_id = b.id
 AND oe.event_type = 'RECEIPT_SUBMITTED'
WHERE b.booking_number = ?
GROUP BY b.id, b.booking_number, b.commission_receipt_file_id;

SELECT COUNT(*) AS idempotency_rows
FROM settlement_receipt_idempotency sri
INNER JOIN bookings b ON b.id = sri.booking_id
WHERE b.booking_number = ?;
