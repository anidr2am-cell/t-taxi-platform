-- TTaxi Platform — Chat MVP (Pack 17)
-- Depends on: 05_chat.sql

USE ttaxi;

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

SET @sender_participant_col_exists = (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'chat_messages'
    AND COLUMN_NAME = 'sender_participant_id'
);

SET @add_sender_participant_col_sql = IF(
  @sender_participant_col_exists = 0,
  'ALTER TABLE chat_messages ADD COLUMN sender_participant_id BIGINT UNSIGNED NULL DEFAULT NULL AFTER sender_user_id',
  'SELECT 1'
);
PREPARE stmt_add_sender_participant_col FROM @add_sender_participant_col_sql;
EXECUTE stmt_add_sender_participant_col;
DEALLOCATE PREPARE stmt_add_sender_participant_col;

SET @client_message_col_exists = (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'chat_messages'
    AND COLUMN_NAME = 'client_message_id'
);

SET @add_client_message_col_sql = IF(
  @client_message_col_exists = 0,
  'ALTER TABLE chat_messages ADD COLUMN client_message_id VARCHAR(36) NULL DEFAULT NULL AFTER content',
  'SELECT 1'
);
PREPARE stmt_add_client_message_col FROM @add_client_message_col_sql;
EXECUTE stmt_add_client_message_col;
DEALLOCATE PREPARE stmt_add_client_message_col;

SET @sender_participant_idx_exists = (
  SELECT COUNT(*)
  FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'chat_messages'
    AND INDEX_NAME = 'idx_chat_messages_sender_participant'
);

SET @add_sender_participant_idx_sql = IF(
  @sender_participant_idx_exists = 0,
  'ALTER TABLE chat_messages ADD KEY idx_chat_messages_sender_participant (sender_participant_id)',
  'SELECT 1'
);
PREPARE stmt_add_sender_participant_idx FROM @add_sender_participant_idx_sql;
EXECUTE stmt_add_sender_participant_idx;
DEALLOCATE PREPARE stmt_add_sender_participant_idx;

SET @client_message_idx_exists = (
  SELECT COUNT(*)
  FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'chat_messages'
    AND INDEX_NAME = 'idx_chat_messages_client_id'
);

SET @add_client_message_idx_sql = IF(
  @client_message_idx_exists = 0,
  'ALTER TABLE chat_messages ADD KEY idx_chat_messages_client_id (chat_room_id, sender_participant_id, client_message_id)',
  'SELECT 1'
);
PREPARE stmt_add_client_message_idx FROM @add_client_message_idx_sql;
EXECUTE stmt_add_client_message_idx;
DEALLOCATE PREPARE stmt_add_client_message_idx;

SET @sender_participant_fk_exists = (
  SELECT COUNT(*)
  FROM information_schema.TABLE_CONSTRAINTS
  WHERE CONSTRAINT_SCHEMA = DATABASE()
    AND TABLE_NAME = 'chat_messages'
    AND CONSTRAINT_NAME = 'fk_chat_messages_sender_participant_id'
    AND CONSTRAINT_TYPE = 'FOREIGN KEY'
);

SET @add_sender_participant_fk_sql = IF(
  @sender_participant_fk_exists = 0,
  'ALTER TABLE chat_messages ADD CONSTRAINT fk_chat_messages_sender_participant_id FOREIGN KEY (sender_participant_id) REFERENCES chat_participants (id) ON DELETE SET NULL ON UPDATE CASCADE',
  'SELECT 1'
);
PREPARE stmt_add_sender_participant_fk FROM @add_sender_participant_fk_sql;
EXECUTE stmt_add_sender_participant_fk;
DEALLOCATE PREPARE stmt_add_sender_participant_fk;

SET @idempotency_idx_exists = (
  SELECT COUNT(*)
  FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'chat_messages'
    AND INDEX_NAME = 'uk_chat_messages_idempotency'
);

SET @add_idempotency_idx_sql = IF(
  @idempotency_idx_exists = 0,
  'ALTER TABLE chat_messages ADD UNIQUE KEY uk_chat_messages_idempotency (chat_room_id, sender_participant_id, client_message_id)',
  'SELECT 1'
);
PREPARE stmt_add_idempotency_idx FROM @add_idempotency_idx_sql;
EXECUTE stmt_add_idempotency_idx;
DEALLOCATE PREPARE stmt_add_idempotency_idx;
