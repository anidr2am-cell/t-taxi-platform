SELECT
  b.status,
  b.commission_status,
  (b.commission_paid_at IS NOT NULL) AS commission_paid_at_set,
  (
    SELECT COUNT(*)
    FROM booking_activity_logs al
    WHERE al.booking_id = b.id
      AND al.activity_type = 'COMMISSION_APPROVED'
  ) AS commission_approved_count,
  (
    SELECT COUNT(*)
    FROM booking_activity_logs al
    WHERE al.booking_id = b.id
      AND al.activity_type = 'MANUAL_SETTLEMENT_APPROVED_WITHOUT_RECEIPT'
  ) AS manual_approved_count,
  (
    SELECT COUNT(*)
    FROM outbox_events oe
    WHERE oe.aggregate_id = b.id
      AND oe.event_type = 'settlement.approved'
  ) AS settlement_approved_outbox_count,
  (
    SELECT COUNT(*)
    FROM booking_driver_assignments bda
    WHERE bda.booking_id = b.id
      AND bda.is_active = 1
      AND bda.deleted_at IS NULL
  ) AS active_assignment_count,
  (
    SELECT COUNT(DISTINCT f.id)
    FROM files f
    WHERE f.entity_id = b.id
      AND f.entity_type = 'COMMISSION_RECEIPT'
      AND f.deleted_at IS NULL
  ) AS active_receipt_files
FROM bookings b
WHERE b.booking_number = '@BOOKING_NUMBER@';
