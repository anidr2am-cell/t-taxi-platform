-- T-Ride driver archive flags.
-- Archives test drivers without deleting users, vehicles, documents, trips, settlements, chats, or reviews.
-- Safe to re-run when columns or indexes already exist.

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

SET @driver_archived_exists = (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'drivers'
    AND COLUMN_NAME = 'is_archived'
);

SET @sql = IF(
  @driver_archived_exists = 0,
  'ALTER TABLE drivers ADD COLUMN is_archived TINYINT(1) NOT NULL DEFAULT 0 AFTER is_active',
  'SELECT 1'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @driver_archived_at_exists = (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'drivers'
    AND COLUMN_NAME = 'archived_at'
);

SET @sql = IF(
  @driver_archived_at_exists = 0,
  'ALTER TABLE drivers ADD COLUMN archived_at DATETIME NULL DEFAULT NULL AFTER is_archived',
  'SELECT 1'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @driver_archived_by_exists = (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'drivers'
    AND COLUMN_NAME = 'archived_by'
);

SET @sql = IF(
  @driver_archived_by_exists = 0,
  'ALTER TABLE drivers ADD COLUMN archived_by BIGINT UNSIGNED NULL DEFAULT NULL AFTER archived_at',
  'SELECT 1'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @driver_archive_reason_exists = (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'drivers'
    AND COLUMN_NAME = 'archive_reason'
);

SET @sql = IF(
  @driver_archive_reason_exists = 0,
  'ALTER TABLE drivers ADD COLUMN archive_reason VARCHAR(64) NULL DEFAULT NULL AFTER archived_by',
  'SELECT 1'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @driver_archived_index_exists = (
  SELECT COUNT(*)
  FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'drivers'
    AND INDEX_NAME = 'idx_drivers_archived'
);

SET @sql = IF(
  @driver_archived_index_exists = 0,
  'CREATE INDEX idx_drivers_archived ON drivers (is_archived, archived_at)',
  'SELECT 1'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;
