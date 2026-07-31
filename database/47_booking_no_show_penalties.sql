-- Admin-recorded no-show penalties (separate from commission settlement).
-- Depends on: 04_booking_core.sql, 01_identity.sql
-- Rerunnable: creates table only when missing.
-- The target database is selected by the migration runner; do not add USE here.

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

SET @booking_no_show_penalties_table_exists = (
  SELECT COUNT(*)
  FROM information_schema.TABLES
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'booking_no_show_penalties'
);

SET @create_booking_no_show_penalties_sql = IF(
  @booking_no_show_penalties_table_exists = 0,
  'CREATE TABLE booking_no_show_penalties (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    booking_id BIGINT UNSIGNED NOT NULL,
    penalty_amount DECIMAL(12, 2) NOT NULL,
    currency CHAR(3) NOT NULL DEFAULT ''THB'',
    reason VARCHAR(1000) NOT NULL,
    created_by_admin_id BIGINT UNSIGNED NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uk_penalty_one_active_per_booking (booking_id),
    CONSTRAINT fk_penalty_booking
      FOREIGN KEY (booking_id) REFERENCES bookings (id)
      ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_penalty_admin
      FOREIGN KEY (created_by_admin_id) REFERENCES users (id)
      ON DELETE RESTRICT ON UPDATE CASCADE
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci',
  'SELECT 1'
);

PREPARE stmt_create_booking_no_show_penalties
  FROM @create_booking_no_show_penalties_sql;
EXECUTE stmt_create_booking_no_show_penalties;
DEALLOCATE PREPARE stmt_create_booking_no_show_penalties;
