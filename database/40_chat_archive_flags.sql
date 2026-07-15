-- T-Ride chat hide/archive flags.
-- Hides test/moderated chat data without deleting messages, rooms, or files.
-- Safe to re-run when columns or indexes already exist.

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

SET @chat_message_hidden_exists = (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'chat_messages'
    AND COLUMN_NAME = 'is_hidden'
);

SET @sql = IF(
  @chat_message_hidden_exists = 0,
  'ALTER TABLE chat_messages ADD COLUMN is_hidden TINYINT(1) NOT NULL DEFAULT 0 AFTER message_status',
  'SELECT 1'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @chat_message_hidden_at_exists = (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'chat_messages'
    AND COLUMN_NAME = 'hidden_at'
);

SET @sql = IF(
  @chat_message_hidden_at_exists = 0,
  'ALTER TABLE chat_messages ADD COLUMN hidden_at DATETIME NULL DEFAULT NULL AFTER is_hidden',
  'SELECT 1'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @chat_message_hidden_by_exists = (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'chat_messages'
    AND COLUMN_NAME = 'hidden_by'
);

SET @sql = IF(
  @chat_message_hidden_by_exists = 0,
  'ALTER TABLE chat_messages ADD COLUMN hidden_by BIGINT UNSIGNED NULL DEFAULT NULL AFTER hidden_at',
  'SELECT 1'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @chat_message_hide_reason_exists = (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'chat_messages'
    AND COLUMN_NAME = 'hide_reason'
);

SET @sql = IF(
  @chat_message_hide_reason_exists = 0,
  'ALTER TABLE chat_messages ADD COLUMN hide_reason VARCHAR(64) NULL DEFAULT NULL AFTER hidden_by',
  'SELECT 1'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @chat_room_archived_exists = (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'chat_rooms'
    AND COLUMN_NAME = 'is_archived'
);

SET @sql = IF(
  @chat_room_archived_exists = 0,
  'ALTER TABLE chat_rooms ADD COLUMN is_archived TINYINT(1) NOT NULL DEFAULT 0 AFTER is_active',
  'SELECT 1'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @chat_room_archived_at_exists = (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'chat_rooms'
    AND COLUMN_NAME = 'archived_at'
);

SET @sql = IF(
  @chat_room_archived_at_exists = 0,
  'ALTER TABLE chat_rooms ADD COLUMN archived_at DATETIME NULL DEFAULT NULL AFTER is_archived',
  'SELECT 1'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @chat_room_archived_by_exists = (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'chat_rooms'
    AND COLUMN_NAME = 'archived_by'
);

SET @sql = IF(
  @chat_room_archived_by_exists = 0,
  'ALTER TABLE chat_rooms ADD COLUMN archived_by BIGINT UNSIGNED NULL DEFAULT NULL AFTER archived_at',
  'SELECT 1'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @chat_room_archive_reason_exists = (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'chat_rooms'
    AND COLUMN_NAME = 'archive_reason'
);

SET @sql = IF(
  @chat_room_archive_reason_exists = 0,
  'ALTER TABLE chat_rooms ADD COLUMN archive_reason VARCHAR(64) NULL DEFAULT NULL AFTER archived_by',
  'SELECT 1'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @chat_message_hidden_index_exists = (
  SELECT COUNT(*)
  FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'chat_messages'
    AND INDEX_NAME = 'idx_chat_messages_hidden_room_time'
);

SET @sql = IF(
  @chat_message_hidden_index_exists = 0,
  'CREATE INDEX idx_chat_messages_hidden_room_time ON chat_messages (chat_room_id, is_hidden, created_at)',
  'SELECT 1'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @chat_room_archived_index_exists = (
  SELECT COUNT(*)
  FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'chat_rooms'
    AND INDEX_NAME = 'idx_chat_rooms_archived'
);

SET @sql = IF(
  @chat_room_archived_index_exists = 0,
  'CREATE INDEX idx_chat_rooms_archived ON chat_rooms (is_archived, archived_at)',
  'SELECT 1'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;
