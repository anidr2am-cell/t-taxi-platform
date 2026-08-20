-- Customer booking preference flags (best-effort hints for dispatch).
-- Rerunnable: adds columns only when they are missing.
-- Depends on: 04_booking_core.sql

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

SET @prefer_female_driver_col_exists = (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'bookings'
    AND COLUMN_NAME = 'prefer_female_driver'
);

SET @add_prefer_female_driver_col_sql = IF(
  @prefer_female_driver_col_exists = 0,
  'ALTER TABLE bookings ADD COLUMN prefer_female_driver TINYINT(1) NOT NULL DEFAULT 0 AFTER special_requests',
  'SELECT 1'
);

PREPARE add_prefer_female_driver_col_stmt FROM @add_prefer_female_driver_col_sql;
EXECUTE add_prefer_female_driver_col_stmt;
DEALLOCATE PREPARE add_prefer_female_driver_col_stmt;

SET @prefer_smoking_vehicle_col_exists = (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'bookings'
    AND COLUMN_NAME = 'prefer_smoking_vehicle'
);

SET @add_prefer_smoking_vehicle_col_sql = IF(
  @prefer_smoking_vehicle_col_exists = 0,
  'ALTER TABLE bookings ADD COLUMN prefer_smoking_vehicle TINYINT(1) NOT NULL DEFAULT 0 AFTER prefer_female_driver',
  'SELECT 1'
);

PREPARE add_prefer_smoking_vehicle_col_stmt FROM @add_prefer_smoking_vehicle_col_sql;
EXECUTE add_prefer_smoking_vehicle_col_stmt;
DEALLOCATE PREPARE add_prefer_smoking_vehicle_col_stmt;
