-- Driver real-time location MVP.
-- Rerunnable migration: augments the existing drivers current-location columns.

USE ttaxi;

SET @schema := DATABASE();

SET @sql := (
  SELECT IF(
    COUNT(*) = 0,
    'ALTER TABLE drivers ADD COLUMN current_accuracy_meters DECIMAL(8, 2) NULL DEFAULT NULL AFTER current_lng',
    'SELECT 1'
  )
  FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = @schema
    AND TABLE_NAME = 'drivers'
    AND COLUMN_NAME = 'current_accuracy_meters'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @sql := (
  SELECT IF(
    COUNT(*) = 0,
    'ALTER TABLE drivers ADD COLUMN current_heading SMALLINT UNSIGNED NULL DEFAULT NULL AFTER current_accuracy_meters',
    'SELECT 1'
  )
  FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = @schema
    AND TABLE_NAME = 'drivers'
    AND COLUMN_NAME = 'current_heading'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @sql := (
  SELECT IF(
    COUNT(*) = 0,
    'ALTER TABLE drivers ADD COLUMN current_speed_kph DECIMAL(6, 2) NULL DEFAULT NULL AFTER current_heading',
    'SELECT 1'
  )
  FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = @schema
    AND TABLE_NAME = 'drivers'
    AND COLUMN_NAME = 'current_speed_kph'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @sql := (
  SELECT IF(
    COUNT(*) = 0,
    'ALTER TABLE drivers ADD COLUMN location_recorded_at DATETIME NULL DEFAULT NULL AFTER current_speed_kph',
    'SELECT 1'
  )
  FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = @schema
    AND TABLE_NAME = 'drivers'
    AND COLUMN_NAME = 'location_recorded_at'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @sql := (
  SELECT IF(
    COUNT(*) = 0,
    'CREATE INDEX idx_drivers_location_online ON drivers (is_online, is_active, location_updated_at)',
    'SELECT 1'
  )
  FROM INFORMATION_SCHEMA.STATISTICS
  WHERE TABLE_SCHEMA = @schema
    AND TABLE_NAME = 'drivers'
    AND INDEX_NAME = 'idx_drivers_location_online'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;
