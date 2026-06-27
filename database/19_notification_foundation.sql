-- TTaxi Platform — Notification foundation (Pack 16)
-- Depends on: 06_notification.sql, 04_booking_core.sql

USE ttaxi;

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

SET @col_exists = (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'notifications' AND COLUMN_NAME = 'recipient_type'
);
SET @sql = IF(
  @col_exists = 0,
  'ALTER TABLE notifications MODIFY COLUMN user_id BIGINT UNSIGNED NULL, MODIFY COLUMN channel ENUM(''PUSH'', ''EMAIL'', ''SMS'', ''IN_APP'') NOT NULL DEFAULT ''IN_APP''',
  'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @col_exists = (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'notifications' AND COLUMN_NAME = 'recipient_type'
);
SET @sql = IF(
  @col_exists = 0,
  'ALTER TABLE notifications ADD COLUMN recipient_type ENUM(''USER'', ''GUEST_BOOKING'') NOT NULL DEFAULT ''USER'' AFTER id',
  'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @col_exists = (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'notifications' AND COLUMN_NAME = 'recipient_driver_id'
);
SET @sql = IF(
  @col_exists = 0,
  'ALTER TABLE notifications ADD COLUMN recipient_driver_id BIGINT UNSIGNED NULL DEFAULT NULL AFTER user_id',
  'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @col_exists = (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'notifications' AND COLUMN_NAME = 'audience_role'
);
SET @sql = IF(
  @col_exists = 0,
  'ALTER TABLE notifications ADD COLUMN audience_role VARCHAR(20) NULL DEFAULT NULL AFTER recipient_driver_id',
  'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @col_exists = (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'notifications' AND COLUMN_NAME = 'event_id'
);
SET @sql = IF(
  @col_exists = 0,
  'ALTER TABLE notifications ADD COLUMN event_id VARCHAR(36) NULL DEFAULT NULL AFTER audience_role',
  'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @col_exists = (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'notifications' AND COLUMN_NAME = 'event_name'
);
SET @sql = IF(
  @col_exists = 0,
  'ALTER TABLE notifications ADD COLUMN event_name VARCHAR(50) NULL DEFAULT NULL AFTER event_id',
  'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @col_exists = (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'notifications' AND COLUMN_NAME = 'idempotency_key'
);
SET @sql = IF(
  @col_exists = 0,
  'ALTER TABLE notifications ADD COLUMN idempotency_key VARCHAR(128) NULL DEFAULT NULL AFTER event_name',
  'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @idx_exists = (
  SELECT COUNT(*) FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'notifications' AND INDEX_NAME = 'uk_notifications_idempotency'
);
SET @sql = IF(
  @idx_exists = 0,
  'ALTER TABLE notifications ADD UNIQUE KEY uk_notifications_idempotency (idempotency_key)',
  'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @idx_exists = (
  SELECT COUNT(*) FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'notifications' AND INDEX_NAME = 'idx_notifications_guest_booking'
);
SET @sql = IF(
  @idx_exists = 0,
  'ALTER TABLE notifications ADD KEY idx_notifications_guest_booking (booking_id, read_at, created_at)',
  'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @idx_exists = (
  SELECT COUNT(*) FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'notifications' AND INDEX_NAME = 'idx_notifications_driver_recipient'
);
SET @sql = IF(
  @idx_exists = 0,
  'ALTER TABLE notifications ADD KEY idx_notifications_driver_recipient (recipient_driver_id, read_at, created_at)',
  'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

CREATE TABLE IF NOT EXISTS notification_deliveries (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  notification_id BIGINT UNSIGNED NOT NULL,
  channel ENUM('IN_APP', 'EMAIL', 'FCM') NOT NULL,
  delivery_status ENUM('PENDING', 'DELIVERED', 'SKIPPED', 'FAILED') NOT NULL DEFAULT 'PENDING',
  attempt_count INT UNSIGNED NOT NULL DEFAULT 0,
  last_error VARCHAR(500) NULL DEFAULT NULL,
  delivered_at DATETIME NULL DEFAULT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_notification_deliveries_notification_channel (notification_id, channel),
  KEY idx_notification_deliveries_status (delivery_status, created_at),
  CONSTRAINT fk_notification_deliveries_notification_id
    FOREIGN KEY (notification_id) REFERENCES notifications (id)
    ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
