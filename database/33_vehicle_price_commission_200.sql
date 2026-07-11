-- T-Ride — Set fixed 200 THB commission on confirmed vehicle_prices rows.
-- Idempotent: adds column if missing, updates only numeric active prices.
-- Preview before apply:
--   SELECT COUNT(*) AS target_count
--   FROM vehicle_prices
--   WHERE deleted_at IS NULL
--     AND is_active = 1
--     AND price > 0;

USE `ttaxi`;

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

SET @schema := DATABASE();

SET @commission_col_exists := (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = @schema
    AND TABLE_NAME = 'vehicle_prices'
    AND COLUMN_NAME = 'commission'
);

SET @add_commission_sql := IF(
  @commission_col_exists = 0,
  'ALTER TABLE vehicle_prices ADD COLUMN commission DECIMAL(12, 2) NULL DEFAULT NULL AFTER price',
  'SELECT 1'
);
PREPARE stmt_add_commission FROM @add_commission_sql;
EXECUTE stmt_add_commission;
DEALLOCATE PREPARE stmt_add_commission;

UPDATE vehicle_prices
SET commission = 200.00,
    updated_at = CURRENT_TIMESTAMP
WHERE deleted_at IS NULL
  AND is_active = 1
  AND price > 0;

INSERT INTO settings (group_name, key_name, value, value_type, is_public, description)
VALUES (
  'settlement',
  'commission_fixed_amount',
  '200',
  'NUMBER',
  0,
  'Fixed platform commission amount (THB) for confirmed fare bookings'
)
ON DUPLICATE KEY UPDATE
  value = VALUES(value),
  value_type = VALUES(value_type),
  description = VALUES(description),
  updated_at = CURRENT_TIMESTAMP;
