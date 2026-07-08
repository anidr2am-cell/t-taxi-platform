-- Support inquiry contact fields, lookup token, and message thread.
-- Rerunnable migration: adds missing columns/tables and preserves existing data.

USE ttaxi;

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

SET @col_exists = (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'support_inquiries'
    AND COLUMN_NAME = 'lookup_token_hash'
);
SET @sql = IF(
  @col_exists = 0,
  'ALTER TABLE support_inquiries ADD COLUMN lookup_token_hash VARCHAR(128) NULL DEFAULT NULL AFTER public_id',
  'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @col_exists = (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'support_inquiries'
    AND COLUMN_NAME = 'kakao_id'
);
SET @sql = IF(
  @col_exists = 0,
  'ALTER TABLE support_inquiries ADD COLUMN kakao_id VARCHAR(100) NULL DEFAULT NULL AFTER customer_email',
  'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @col_exists = (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'support_inquiries'
    AND COLUMN_NAME = 'line_id'
);
SET @sql = IF(
  @col_exists = 0,
  'ALTER TABLE support_inquiries ADD COLUMN line_id VARCHAR(100) NULL DEFAULT NULL AFTER kakao_id',
  'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @idx_exists = (
  SELECT COUNT(*) FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'support_inquiries'
    AND INDEX_NAME = 'idx_support_inquiries_lookup_token_hash'
);
SET @sql = IF(
  @idx_exists = 0,
  'ALTER TABLE support_inquiries ADD KEY idx_support_inquiries_lookup_token_hash (lookup_token_hash)',
  'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @idx_exists = (
  SELECT COUNT(*) FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'support_inquiries'
    AND INDEX_NAME = 'idx_support_inquiries_updated_at'
);
SET @sql = IF(
  @idx_exists = 0,
  'ALTER TABLE support_inquiries ADD KEY idx_support_inquiries_updated_at (updated_at)',
  'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

CREATE TABLE IF NOT EXISTS support_inquiry_messages (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  inquiry_id BIGINT UNSIGNED NOT NULL,
  sender_type ENUM('CUSTOMER', 'ADMIN', 'SYSTEM') NOT NULL,
  sender_user_id BIGINT UNSIGNED NULL DEFAULT NULL,
  message TEXT NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  deleted_at DATETIME NULL DEFAULT NULL,
  PRIMARY KEY (id),
  KEY idx_support_inquiry_messages_inquiry_id_created_at (inquiry_id, created_at),
  KEY idx_support_inquiry_messages_sender_user_id (sender_user_id),
  CONSTRAINT fk_support_inquiry_messages_inquiry
    FOREIGN KEY (inquiry_id) REFERENCES support_inquiries (id)
    ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO support_inquiry_messages (inquiry_id, sender_type, message, created_at)
SELECT si.id, 'CUSTOMER', si.message, si.created_at
FROM support_inquiries si
WHERE si.deleted_at IS NULL
  AND NOT EXISTS (
    SELECT 1
    FROM support_inquiry_messages sim
    WHERE sim.inquiry_id = si.id
      AND sim.deleted_at IS NULL
  );
