-- Roll back database/69_settlement_timestamps_bangkok.sql.
-- Run only after confirming the migration marker exists and before any new
-- commission_paid_at value has been written by the updated application.
START TRANSACTION;
UPDATE bookings
SET commission_paid_at = DATE_SUB(commission_paid_at, INTERVAL 7 HOUR)
WHERE commission_paid_at IS NOT NULL;
DELETE FROM settings
WHERE group_name = 'migration'
  AND key_name = '69_settlement_timestamps_bangkok';
COMMIT;
