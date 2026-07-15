-- T-Ride booking archive flags.
-- Archives test bookings without deleting booking or child records.
-- Safe to re-run when columns already exist.

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

SET @is_archived_exists = (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'bookings'
    AND COLUMN_NAME = 'is_archived'
);

SET @sql = IF(
  @is_archived_exists = 0,
  'ALTER TABLE bookings ADD COLUMN is_archived TINYINT(1) NOT NULL DEFAULT 0 AFTER deleted_at',
  'SELECT 1'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @archived_at_exists = (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'bookings'
    AND COLUMN_NAME = 'archived_at'
);

SET @sql = IF(
  @archived_at_exists = 0,
  'ALTER TABLE bookings ADD COLUMN archived_at DATETIME NULL DEFAULT NULL AFTER is_archived',
  'SELECT 1'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @archived_by_exists = (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'bookings'
    AND COLUMN_NAME = 'archived_by'
);

SET @sql = IF(
  @archived_by_exists = 0,
  'ALTER TABLE bookings ADD COLUMN archived_by BIGINT UNSIGNED NULL DEFAULT NULL AFTER archived_at',
  'SELECT 1'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @archive_reason_exists = (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'bookings'
    AND COLUMN_NAME = 'archive_reason'
);

SET @sql = IF(
  @archive_reason_exists = 0,
  'ALTER TABLE bookings ADD COLUMN archive_reason VARCHAR(64) NULL DEFAULT NULL AFTER archived_by',
  'SELECT 1'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @archive_index_exists = (
  SELECT COUNT(*)
  FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'bookings'
    AND INDEX_NAME = 'idx_bookings_archived'
);

SET @sql = IF(
  @archive_index_exists = 0,
  'CREATE INDEX idx_bookings_archived ON bookings (is_archived, archived_at)',
  'SELECT 1'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;
