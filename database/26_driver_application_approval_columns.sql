-- Add approval/rejection audit columns used by driver application review flow.
-- Depends on: 24_driver_applications.sql, 25_driver_application_signup.sql

USE ttaxi;

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

SET @col_exists = (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'driver_applications' AND COLUMN_NAME = 'approved_at'
);
SET @sql = IF(
  @col_exists = 0,
  'ALTER TABLE driver_applications ADD COLUMN approved_at DATETIME NULL DEFAULT NULL AFTER approved_driver_id',
  'SELECT 1'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @col_exists = (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'driver_applications' AND COLUMN_NAME = 'approved_by'
);
SET @sql = IF(
  @col_exists = 0,
  'ALTER TABLE driver_applications ADD COLUMN approved_by BIGINT UNSIGNED NULL DEFAULT NULL AFTER approved_at',
  'SELECT 1'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @col_exists = (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'driver_applications' AND COLUMN_NAME = 'rejected_at'
);
SET @sql = IF(
  @col_exists = 0,
  'ALTER TABLE driver_applications ADD COLUMN rejected_at DATETIME NULL DEFAULT NULL AFTER admin_note',
  'SELECT 1'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @col_exists = (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'driver_applications' AND COLUMN_NAME = 'rejected_by'
);
SET @sql = IF(
  @col_exists = 0,
  'ALTER TABLE driver_applications ADD COLUMN rejected_by BIGINT UNSIGNED NULL DEFAULT NULL AFTER rejected_at',
  'SELECT 1'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @idx_exists = (
  SELECT COUNT(*) FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'driver_applications' AND INDEX_NAME = 'idx_driver_applications_approved_at'
);
SET @sql = IF(
  @idx_exists = 0,
  'ALTER TABLE driver_applications ADD KEY idx_driver_applications_approved_at (approved_at)',
  'SELECT 1'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @idx_exists = (
  SELECT COUNT(*) FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'driver_applications' AND INDEX_NAME = 'idx_driver_applications_approved_by'
);
SET @sql = IF(
  @idx_exists = 0,
  'ALTER TABLE driver_applications ADD KEY idx_driver_applications_approved_by (approved_by)',
  'SELECT 1'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @idx_exists = (
  SELECT COUNT(*) FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'driver_applications' AND INDEX_NAME = 'idx_driver_applications_rejected_at'
);
SET @sql = IF(
  @idx_exists = 0,
  'ALTER TABLE driver_applications ADD KEY idx_driver_applications_rejected_at (rejected_at)',
  'SELECT 1'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @idx_exists = (
  SELECT COUNT(*) FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'driver_applications' AND INDEX_NAME = 'idx_driver_applications_rejected_by'
);
SET @sql = IF(
  @idx_exists = 0,
  'ALTER TABLE driver_applications ADD KEY idx_driver_applications_rejected_by (rejected_by)',
  'SELECT 1'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @fk_exists = (
  SELECT COUNT(*) FROM information_schema.TABLE_CONSTRAINTS
  WHERE CONSTRAINT_SCHEMA = DATABASE()
    AND TABLE_NAME = 'driver_applications'
    AND CONSTRAINT_NAME = 'fk_driver_applications_approved_by'
    AND CONSTRAINT_TYPE = 'FOREIGN KEY'
);
SET @sql = IF(
  @fk_exists = 0,
  'ALTER TABLE driver_applications ADD CONSTRAINT fk_driver_applications_approved_by FOREIGN KEY (approved_by) REFERENCES users (id) ON DELETE SET NULL ON UPDATE CASCADE',
  'SELECT 1'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @fk_exists = (
  SELECT COUNT(*) FROM information_schema.TABLE_CONSTRAINTS
  WHERE CONSTRAINT_SCHEMA = DATABASE()
    AND TABLE_NAME = 'driver_applications'
    AND CONSTRAINT_NAME = 'fk_driver_applications_rejected_by'
    AND CONSTRAINT_TYPE = 'FOREIGN KEY'
);
SET @sql = IF(
  @fk_exists = 0,
  'ALTER TABLE driver_applications ADD CONSTRAINT fk_driver_applications_rejected_by FOREIGN KEY (rejected_by) REFERENCES users (id) ON DELETE SET NULL ON UPDATE CASCADE',
  'SELECT 1'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;
