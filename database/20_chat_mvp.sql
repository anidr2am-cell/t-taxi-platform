-- TTaxi Platform — Chat MVP (Pack 17)
-- Depends on: 05_chat.sql

USE ttaxi;

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

ALTER TABLE chat_messages
  ADD COLUMN sender_participant_id BIGINT UNSIGNED NULL DEFAULT NULL AFTER sender_user_id,
  ADD COLUMN client_message_id VARCHAR(36) NULL DEFAULT NULL AFTER content,
  ADD KEY idx_chat_messages_sender_participant (sender_participant_id),
  ADD KEY idx_chat_messages_client_id (chat_room_id, sender_participant_id, client_message_id),
  ADD CONSTRAINT fk_chat_messages_sender_participant_id
    FOREIGN KEY (sender_participant_id) REFERENCES chat_participants (id)
    ON DELETE SET NULL ON UPDATE CASCADE,
  ADD UNIQUE KEY uk_chat_messages_idempotency (
    chat_room_id, sender_participant_id, client_message_id
  );
