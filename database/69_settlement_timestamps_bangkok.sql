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
WHERE commission_paid_at IS NOT NULL AND @settlement_ts_v2_done = 0
  AND (
    -- 47 rows have a matching UTC approval instant in metadata.
    (
      JSON_UNQUOTE(JSON_EXTRACT(metadata, '$.commissionApprovedAt')) REGEXP 'Z$'
      AND ABS(TIMESTAMPDIFF(SECOND, commission_paid_at,
        STR_TO_DATE(LEFT(REPLACE(JSON_UNQUOTE(JSON_EXTRACT(metadata,
          '$.commissionApprovedAt')), 'T', ' '), 19), '%Y-%m-%d %H:%i:%s'))) <= 2
    )
    -- These five receipt-approved rows predate approval metadata. Their paid
    -- timestamps are exactly seven hours before completion, matching the old
    -- UTC writer against the Asia/Bangkok completion timestamp.
    OR booking_number IN (
      'TX202607090005',
      'TX202607110002',
      'TX202607110003',
      'TX202607120002',
      'TX202607130002'
    )
  );

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
