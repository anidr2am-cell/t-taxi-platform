-- TTaxi Platform — Chat (MySQL 8)
-- Depends on: 00_database.sql through 04_booking_core.sql

USE ttaxi;

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- chat_rooms
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS chat_rooms (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  booking_id BIGINT UNSIGNED NOT NULL,
  room_code VARCHAR(50) NOT NULL,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at DATETIME NULL DEFAULT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_chat_rooms_code (room_code),
  UNIQUE KEY uk_chat_rooms_booking (booking_id),
  CONSTRAINT fk_chat_rooms_booking_id
    FOREIGN KEY (booking_id) REFERENCES bookings (id)
    ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- chat_participants
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS chat_participants (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  chat_room_id BIGINT UNSIGNED NOT NULL,
  user_id BIGINT UNSIGNED NULL DEFAULT NULL,
  participant_role ENUM('CUSTOMER', 'DRIVER', 'ADMIN') NOT NULL,
  display_name VARCHAR(100) NOT NULL,
  last_read_at DATETIME NULL DEFAULT NULL,
  joined_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at DATETIME NULL DEFAULT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_chat_participants_room_role_user (
    chat_room_id, participant_role, user_id
  ),
  CONSTRAINT fk_chat_participants_chat_room_id
    FOREIGN KEY (chat_room_id) REFERENCES chat_rooms (id)
    ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT fk_chat_participants_user_id
    FOREIGN KEY (user_id) REFERENCES users (id)
    ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- chat_messages
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS chat_messages (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  chat_room_id BIGINT UNSIGNED NOT NULL,
  sender_user_id BIGINT UNSIGNED NULL DEFAULT NULL,
  sender_role ENUM('CUSTOMER', 'DRIVER', 'ADMIN') NOT NULL,
  sender_name VARCHAR(100) NOT NULL,
  message_type ENUM('TEXT', 'IMAGE', 'FILE', 'SYSTEM') NOT NULL DEFAULT 'TEXT',
  content TEXT NOT NULL,
  reply_message_id BIGINT UNSIGNED NULL DEFAULT NULL,
  message_status ENUM('SENT', 'DELIVERED', 'READ') NOT NULL DEFAULT 'SENT',
  delivered_at DATETIME NULL DEFAULT NULL,
  metadata JSON NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at DATETIME NULL DEFAULT NULL,
  PRIMARY KEY (id),
  KEY idx_chat_messages_room_time (chat_room_id, created_at),
  KEY idx_chat_messages_reply (reply_message_id),
  KEY idx_chat_messages_status (message_status),
  CONSTRAINT fk_chat_messages_chat_room_id
    FOREIGN KEY (chat_room_id) REFERENCES chat_rooms (id)
    ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT fk_chat_messages_sender_user_id
    FOREIGN KEY (sender_user_id) REFERENCES users (id)
    ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT fk_chat_messages_reply_message_id
    FOREIGN KEY (reply_message_id) REFERENCES chat_messages (id)
    ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- chat_message_reads
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS chat_message_reads (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  chat_message_id BIGINT UNSIGNED NOT NULL,
  chat_participant_id BIGINT UNSIGNED NOT NULL,
  read_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_chat_message_reads_message_participant (
    chat_message_id, chat_participant_id
  ),
  CONSTRAINT fk_chat_message_reads_message_id
    FOREIGN KEY (chat_message_id) REFERENCES chat_messages (id)
    ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT fk_chat_message_reads_participant_id
    FOREIGN KEY (chat_participant_id) REFERENCES chat_participants (id)
    ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
