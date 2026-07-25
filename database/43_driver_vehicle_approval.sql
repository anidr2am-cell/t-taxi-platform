-- Driver vehicle approval status for post-onboarding vehicle registration.
-- Matching already requires driver_vehicles.is_active = 1; pending/rejected stay inactive.
-- Depends on: 03_fleet_places.sql, 07_storage.sql

USE ttaxi;

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

SET @col_exists = (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'driver_vehicles'
    AND COLUMN_NAME = 'approval_status'
);
SET @sql = IF(
  @col_exists = 0,
  'ALTER TABLE driver_vehicles ADD COLUMN approval_status ENUM(''PENDING'', ''APPROVED'', ''REJECTED'') NOT NULL DEFAULT ''APPROVED'' AFTER is_active',
  'SELECT 1'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @col_exists = (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'driver_vehicles'
    AND COLUMN_NAME = 'rejection_reason'
);
SET @sql = IF(
  @col_exists = 0,
  'ALTER TABLE driver_vehicles ADD COLUMN rejection_reason VARCHAR(500) NULL DEFAULT NULL AFTER approval_status',
  'SELECT 1'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @idx_exists = (
  SELECT COUNT(*) FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'driver_vehicles'
    AND INDEX_NAME = 'idx_driver_vehicles_driver_approval'
);
SET @sql = IF(
  @idx_exists = 0,
  'ALTER TABLE driver_vehicles ADD KEY idx_driver_vehicles_driver_approval (driver_id, approval_status, is_active)',
  'SELECT 1'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

CREATE TABLE IF NOT EXISTS driver_vehicle_files (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  driver_vehicle_id BIGINT UNSIGNED NOT NULL,
  file_id BIGINT UNSIGNED NOT NULL,
  category ENUM(
    'DRIVER_VEHICLE_PHOTO',
    'DRIVER_INSURANCE_CERTIFICATE',
    'DRIVER_VEHICLE_REGISTRATION',
    'DRIVER_TAX_CERTIFICATE'
  ) NOT NULL,
  sort_order SMALLINT UNSIGNED NOT NULL DEFAULT 0,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_driver_vehicle_files_file (file_id),
  KEY idx_driver_vehicle_files_vehicle_category (driver_vehicle_id, category, sort_order),
  CONSTRAINT fk_driver_vehicle_files_vehicle_id
    FOREIGN KEY (driver_vehicle_id) REFERENCES driver_vehicles (id)
    ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT fk_driver_vehicle_files_file_id
    FOREIGN KEY (file_id) REFERENCES files (id)
    ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
