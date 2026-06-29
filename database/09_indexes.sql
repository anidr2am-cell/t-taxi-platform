-- TTaxi Platform — Supplemental indexes (MySQL 8)
-- Depends on: 00_database.sql through 08_platform.sql
-- Run after all tables are created.

USE ttaxi;

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Partial-style indexes for active (non-deleted) rows (MySQL 8.0.13+ functional)

DROP PROCEDURE IF EXISTS sp_add_index_if_missing;

DELIMITER $$

CREATE PROCEDURE sp_add_index_if_missing(
  IN p_table_name VARCHAR(64),
  IN p_index_name VARCHAR(64),
  IN p_create_sql TEXT
)
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.STATISTICS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = p_table_name
      AND INDEX_NAME = p_index_name
  ) THEN
    SET @create_index_sql = p_create_sql;
    PREPARE stmt_create_index FROM @create_index_sql;
    EXECUTE stmt_create_index;
    DEALLOCATE PREPARE stmt_create_index;
  END IF;
END$$

DELIMITER ;

CALL sp_add_index_if_missing(
  'bookings',
  'idx_bookings_active_status_scheduled',
  'CREATE INDEX idx_bookings_active_status_scheduled ON bookings (status, scheduled_pickup_at, deleted_at)'
);

CALL sp_add_index_if_missing(
  'bookings',
  'idx_bookings_active_created',
  'CREATE INDEX idx_bookings_active_created ON bookings (created_at, deleted_at)'
);

CALL sp_add_index_if_missing(
  'drivers',
  'idx_drivers_active_online',
  'CREATE INDEX idx_drivers_active_online ON drivers (is_online, status, last_seen_at, deleted_at)'
);

CALL sp_add_index_if_missing(
  'chat_messages',
  'idx_chat_messages_active_room_time',
  'CREATE INDEX idx_chat_messages_active_room_time ON chat_messages (chat_room_id, created_at, deleted_at)'
);

CALL sp_add_index_if_missing(
  'booking_charge_items',
  'idx_booking_charge_items_active_booking',
  'CREATE INDEX idx_booking_charge_items_active_booking ON booking_charge_items (booking_id, deleted_at)'
);

CALL sp_add_index_if_missing(
  'files',
  'idx_files_active_entity',
  'CREATE INDEX idx_files_active_entity ON files (entity_type, entity_id, deleted_at)'
);

DROP PROCEDURE IF EXISTS sp_add_index_if_missing;
