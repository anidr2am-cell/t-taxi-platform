-- One-time correction for commission_paid_at values written as UTC wall-clock
-- before settlement timestamps adopted the Asia/Bangkok DATETIME contract.
SET @settlement_ts_v2_done = (
  SELECT COUNT(*)
  FROM settings
  WHERE group_name = 'migration'
    AND key_name = '69_settlement_timestamps_bangkok'
    AND deleted_at IS NULL
);

SET @settlement_ts_v2_sql = IF(
  @settlement_ts_v2_done = 0,
  'UPDATE bookings SET commission_paid_at = DATE_ADD(commission_paid_at, INTERVAL 7 HOUR) WHERE commission_paid_at IS NOT NULL',
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
