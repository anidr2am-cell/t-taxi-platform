-- One-time correction for commission_paid_at values written as UTC wall-clock
-- before settlement timestamps adopted the Asia/Bangkok DATETIME contract.
-- Keep the original values for an exact rollback. Run while settlement writes
-- are paused, before starting the new backend. DDL is outside the transaction.
CREATE TABLE IF NOT EXISTS migration_69_settlement_paid_backup (
  booking_id BIGINT UNSIGNED NOT NULL PRIMARY KEY,
  original_paid_at DATETIME NOT NULL,
  corrected_paid_at DATETIME NOT NULL
) ENGINE=InnoDB;

START TRANSACTION;
SET @settlement_ts_v2_done = (
  SELECT COUNT(*)
  FROM settings
  WHERE group_name = 'migration'
    AND key_name = '69_settlement_timestamps_bangkok'
    AND deleted_at IS NULL
);

INSERT IGNORE INTO migration_69_settlement_paid_backup
  (booking_id, original_paid_at, corrected_paid_at)
SELECT id, commission_paid_at, DATE_ADD(commission_paid_at, INTERVAL 7 HOUR)
FROM bookings
WHERE commission_paid_at IS NOT NULL AND @settlement_ts_v2_done = 0;

SET @settlement_ts_v2_sql = IF(
  @settlement_ts_v2_done = 0,
  'UPDATE bookings b JOIN migration_69_settlement_paid_backup s ON s.booking_id = b.id SET b.commission_paid_at = s.corrected_paid_at WHERE b.commission_paid_at = s.original_paid_at',
  'SELECT 1'
);
PREPARE settlement_ts_v2_stmt FROM @settlement_ts_v2_sql;
EXECUTE settlement_ts_v2_stmt;
DEALLOCATE PREPARE settlement_ts_v2_stmt;

INSERT INTO settings (
  group_name, key_name, value, data_type, is_encrypted, description
)
SELECT
  'migration',
  '69_settlement_timestamps_bangkok',
  'applied',
  'STRING',
  0,
  'Shift legacy commission_paid_at UTC wall-clock values to Asia/Bangkok wall-clock'
WHERE @settlement_ts_v2_done = 0;
COMMIT;
