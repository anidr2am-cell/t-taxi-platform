-- Extend driver applications into public driver signup with documents.
-- Depends on: 07_storage.sql, 24_driver_applications.sql

USE ttaxi;

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

SET @col_exists = (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'driver_applications' AND COLUMN_NAME = 'bank_name'
);
SET @sql = IF(@col_exists = 0, 'ALTER TABLE driver_applications ADD COLUMN bank_name VARCHAR(100) NULL DEFAULT NULL AFTER notes', 'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @col_exists = (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'driver_applications' AND COLUMN_NAME = 'bank_account_number'
);
SET @sql = IF(@col_exists = 0, 'ALTER TABLE driver_applications ADD COLUMN bank_account_number VARCHAR(80) NULL DEFAULT NULL AFTER bank_name', 'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @col_exists = (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'driver_applications' AND COLUMN_NAME = 'bank_account_holder'
);
SET @sql = IF(@col_exists = 0, 'ALTER TABLE driver_applications ADD COLUMN bank_account_holder VARCHAR(100) NULL DEFAULT NULL AFTER bank_account_number', 'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @col_exists = (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'driver_applications' AND COLUMN_NAME = 'line_id'
);
SET @sql = IF(@col_exists = 0, 'ALTER TABLE driver_applications ADD COLUMN line_id VARCHAR(100) NULL DEFAULT NULL AFTER bank_account_holder', 'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @col_exists = (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'driver_applications' AND COLUMN_NAME = 'primary_service_area'
);
SET @sql = IF(@col_exists = 0, 'ALTER TABLE driver_applications ADD COLUMN primary_service_area VARCHAR(100) NULL DEFAULT NULL AFTER line_id', 'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @idx_exists = (
  SELECT COUNT(*) FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'driver_applications' AND INDEX_NAME = 'idx_driver_applications_phone'
);
SET @sql = IF(@idx_exists = 0, 'ALTER TABLE driver_applications ADD KEY idx_driver_applications_phone (phone)', 'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

CREATE TABLE IF NOT EXISTS driver_application_files (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  driver_application_id BIGINT UNSIGNED NOT NULL,
  file_id BIGINT UNSIGNED NOT NULL,
  category ENUM(
    'DRIVER_LINE_QR',
    'DRIVER_VEHICLE_PHOTO',
    'DRIVER_INSURANCE_CERTIFICATE',
    'DRIVER_VEHICLE_REGISTRATION',
    'DRIVER_TAX_CERTIFICATE'
  ) NOT NULL,
  sort_order SMALLINT UNSIGNED NOT NULL DEFAULT 0,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_driver_application_files_file (file_id),
  KEY idx_driver_application_files_app_category (driver_application_id, category, sort_order),
  CONSTRAINT fk_driver_application_files_application_id
    FOREIGN KEY (driver_application_id) REFERENCES driver_applications (id)
    ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT fk_driver_application_files_file_id
    FOREIGN KEY (file_id) REFERENCES files (id)
    ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
