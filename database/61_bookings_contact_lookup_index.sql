-- Guest contact lookup: normalized phone digits generated column + index
-- Depends on: bookings table with customer_phone, is_archived, deleted_at
-- Additive + rerunnable.

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

DROP PROCEDURE IF EXISTS sp_apply_bookings_contact_lookup_index;

DELIMITER $$

CREATE PROCEDURE sp_apply_bookings_contact_lookup_index()
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 'bookings'
      AND COLUMN_NAME = 'customer_phone_digits'
  ) THEN
    ALTER TABLE bookings
      ADD COLUMN customer_phone_digits VARCHAR(30)
      GENERATED ALWAYS AS (REGEXP_REPLACE(customer_phone, '[^0-9]', '')) STORED
      AFTER customer_phone;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM information_schema.STATISTICS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 'bookings'
      AND INDEX_NAME = 'idx_bookings_contact_lookup'
  ) THEN
    ALTER TABLE bookings DROP INDEX idx_bookings_contact_lookup;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.STATISTICS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 'bookings'
      AND INDEX_NAME = 'idx_bookings_contact_lookup_phone_digits'
  ) THEN
    ALTER TABLE bookings
      ADD INDEX idx_bookings_contact_lookup_phone_digits (
        customer_phone_digits,
        is_archived,
        deleted_at
      );
  END IF;
END$$

DELIMITER ;

CALL sp_apply_bookings_contact_lookup_index();

DROP PROCEDURE IF EXISTS sp_apply_bookings_contact_lookup_index;
