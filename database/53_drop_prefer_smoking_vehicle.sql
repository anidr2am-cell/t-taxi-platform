-- Drop smoking-vehicle preference column (feature removed).
-- Rerunnable: drops column only when it exists.
-- Depends on: 52_booking_preference_options.sql

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

SET @prefer_smoking_vehicle_col_exists = (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'bookings'
    AND COLUMN_NAME = 'prefer_smoking_vehicle'
);

SET @drop_prefer_smoking_vehicle_col_sql = IF(
  @prefer_smoking_vehicle_col_exists > 0,
  'ALTER TABLE bookings DROP COLUMN prefer_smoking_vehicle',
  'SELECT 1'
);

PREPARE drop_prefer_smoking_vehicle_col_stmt FROM @drop_prefer_smoking_vehicle_col_sql;
EXECUTE drop_prefer_smoking_vehicle_col_stmt;
DEALLOCATE PREPARE drop_prefer_smoking_vehicle_col_stmt;
