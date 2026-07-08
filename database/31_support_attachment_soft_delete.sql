-- Support inquiry attachment soft-delete column.
-- Rerunnable migration: adds missing column/index and preserves existing data.

USE ttaxi;

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

SET @col_exists = (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'support_inquiry_attachments'
    AND COLUMN_NAME = 'deleted_at'
);
SET @sql = IF(
  @col_exists = 0,
  'ALTER TABLE support_inquiry_attachments ADD COLUMN deleted_at DATETIME NULL DEFAULT NULL AFTER created_at',
  'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @idx_exists = (
  SELECT COUNT(*) FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'support_inquiry_attachments'
    AND INDEX_NAME = 'idx_support_inquiry_attachments_deleted_at'
);
SET @sql = IF(
  @idx_exists = 0,
  'ALTER TABLE support_inquiry_attachments ADD KEY idx_support_inquiry_attachments_deleted_at (deleted_at)',
  'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;
