-- TTaxi Platform — Supplemental indexes (MySQL 8)
-- Depends on: 00_database.sql through 08_platform.sql
-- Run after all tables are created.

USE ttaxi;

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Partial-style indexes for active (non-deleted) rows (MySQL 8.0.13+ functional)

CREATE INDEX idx_bookings_active_status_scheduled
  ON bookings (status, scheduled_pickup_at, deleted_at);

CREATE INDEX idx_bookings_active_created
  ON bookings (created_at, deleted_at);

CREATE INDEX idx_drivers_active_online
  ON drivers (is_online, status, last_seen_at, deleted_at);

CREATE INDEX idx_chat_messages_active_room_time
  ON chat_messages (chat_room_id, created_at, deleted_at);

CREATE INDEX idx_booking_charge_items_active_booking
  ON booking_charge_items (booking_id, deleted_at);

CREATE INDEX idx_files_active_entity
  ON files (entity_type, entity_id, deleted_at);
