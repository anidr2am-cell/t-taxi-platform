-- Roll back database/69_settlement_timestamps_bangkok.sql.
-- Run only after confirming the migration marker exists and before any new
-- commission_paid_at value has been written by the updated application.
START TRANSACTION;
UPDATE bookings b
JOIN migration_69_settlement_paid_backup s ON s.booking_id = b.id
SET b.commission_paid_at = s.original_paid_at
WHERE b.commission_paid_at = s.corrected_paid_at
  AND EXISTS (SELECT 1 FROM settings WHERE group_name = 'migration'
    AND key_name = '69_settlement_timestamps_bangkok' AND deleted_at IS NULL);
DELETE FROM settings
WHERE group_name = 'migration'
  AND key_name = '69_settlement_timestamps_bangkok';
COMMIT;
-- Retain the snapshot table for audit. Do not rerun the migration after new
-- settlement writes without reviewing the snapshot and taking a new backup.
