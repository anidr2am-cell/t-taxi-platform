-- ---------------------------------------------------------------------------
-- Notification device registration ownership + token hash
-- ---------------------------------------------------------------------------

USE ttaxi;

SET @col_exists = (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'notification_devices'
    AND COLUMN_NAME = 'booking_id'
);
SET @sql = IF(
  @col_exists = 0,
  'ALTER TABLE notification_devices ADD COLUMN booking_id BIGINT UNSIGNED NULL DEFAULT NULL AFTER user_id',
  'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @nullable_user = (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'notification_devices'
    AND COLUMN_NAME = 'user_id'
    AND IS_NULLABLE = 'YES'
);
SET @sql = IF(
  @nullable_user = 0,
  'ALTER TABLE notification_devices MODIFY COLUMN user_id BIGINT UNSIGNED NULL',
  'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @col_exists = (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'notification_devices'
    AND COLUMN_NAME = 'fcm_token_hash'
);
SET @sql = IF(
  @col_exists = 0,
  'ALTER TABLE notification_devices ADD COLUMN fcm_token_hash CHAR(64) NULL DEFAULT NULL AFTER fcm_token',
  'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @col_exists = (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'notification_devices'
    AND COLUMN_NAME = 'device_name'
);
SET @sql = IF(
  @col_exists = 0,
  'ALTER TABLE notification_devices ADD COLUMN device_name VARCHAR(100) NULL DEFAULT NULL AFTER device_id',
  'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @col_exists = (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'notification_devices'
    AND COLUMN_NAME = 'app_version'
);
SET @sql = IF(
  @col_exists = 0,
  'ALTER TABLE notification_devices ADD COLUMN app_version VARCHAR(50) NULL DEFAULT NULL AFTER device_name',
  'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @col_exists = (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'notification_devices'
    AND COLUMN_NAME = 'last_seen_at'
);
SET @sql = IF(
  @col_exists = 0,
  'ALTER TABLE notification_devices ADD COLUMN last_seen_at DATETIME NULL DEFAULT NULL AFTER is_active',
  'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

UPDATE notification_devices
SET last_seen_at = COALESCE(last_seen_at, last_used_at, updated_at, created_at)
WHERE last_seen_at IS NULL;

SET @idx_exists = (
  SELECT COUNT(*) FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'notification_devices'
    AND INDEX_NAME = 'uk_notification_devices_token_hash'
);
SET @sql = IF(
  @idx_exists = 0,
  'ALTER TABLE notification_devices ADD UNIQUE KEY uk_notification_devices_token_hash (fcm_token_hash)',
  'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @idx_exists = (
  SELECT COUNT(*) FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'notification_devices'
    AND INDEX_NAME = 'idx_notification_devices_booking_active'
);
SET @sql = IF(
  @idx_exists = 0,
  'ALTER TABLE notification_devices ADD KEY idx_notification_devices_booking_active (booking_id, is_active, deleted_at)',
  'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @fk_exists = (
  SELECT COUNT(*) FROM information_schema.TABLE_CONSTRAINTS
  WHERE CONSTRAINT_SCHEMA = DATABASE()
    AND TABLE_NAME = 'notification_devices'
    AND CONSTRAINT_NAME = 'fk_notification_devices_booking_id'
    AND CONSTRAINT_TYPE = 'FOREIGN KEY'
);
SET @sql = IF(
  @fk_exists = 0,
  'ALTER TABLE notification_devices ADD CONSTRAINT fk_notification_devices_booking_id FOREIGN KEY (booking_id) REFERENCES bookings (id) ON DELETE CASCADE ON UPDATE CASCADE',
  'SELECT 1'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

DELETE FROM notification_devices
WHERE user_id IS NULL
  AND booking_id IS NULL;

UPDATE notification_devices
SET booking_id = NULL
WHERE user_id IS NOT NULL
  AND booking_id IS NOT NULL;
