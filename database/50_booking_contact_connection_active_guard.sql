-- Booking contact connection active guard (one active connection per booking).
-- Depends on: 49_booking_contact_connection.sql
-- Additive + rerunnable. Refuses to apply when duplicate active rows exist.

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

DROP PROCEDURE IF EXISTS sp_apply_booking_contact_connection_active_guard;

DELIMITER $$

CREATE PROCEDURE sp_apply_booking_contact_connection_active_guard()
BEGIN
  DECLARE v_duplicate_count INT DEFAULT 0;

  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.TABLES
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 'booking_contact_connections'
  ) THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'booking_contact_connections table is required before active guard migration';
  END IF;

  SELECT COUNT(*) INTO v_duplicate_count
  FROM (
    SELECT booking_id
    FROM booking_contact_connections
    WHERE status IN ('PENDING', 'CONFIRM_REQUESTED', 'VERIFIED')
    GROUP BY booking_id
    HAVING COUNT(*) > 1
  ) dup;

  IF v_duplicate_count > 0 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Cannot add uk_bcc_one_active_per_booking: duplicate active contact connections exist';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 'booking_contact_connections'
      AND COLUMN_NAME = 'active_connection_guard'
  ) THEN
    ALTER TABLE booking_contact_connections
      ADD COLUMN active_connection_guard BIGINT UNSIGNED
      GENERATED ALWAYS AS (
        CASE
          WHEN status IN ('PENDING', 'CONFIRM_REQUESTED', 'VERIFIED')
          THEN booking_id
          ELSE NULL
        END
      ) STORED;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.STATISTICS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 'booking_contact_connections'
      AND INDEX_NAME = 'uk_bcc_one_active_per_booking'
  ) THEN
    IF EXISTS (
      SELECT 1
      FROM information_schema.COLUMNS
      WHERE TABLE_SCHEMA = DATABASE()
        AND TABLE_NAME = 'booking_contact_connections'
        AND COLUMN_NAME = 'active_connection_guard'
    ) THEN
      ALTER TABLE booking_contact_connections
        ADD UNIQUE KEY uk_bcc_one_active_per_booking (active_connection_guard);
    END IF;
  END IF;
END$$

DELIMITER ;

CALL sp_apply_booking_contact_connection_active_guard();

DROP PROCEDURE IF EXISTS sp_apply_booking_contact_connection_active_guard;
