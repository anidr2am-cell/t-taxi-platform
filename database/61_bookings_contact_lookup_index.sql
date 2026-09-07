-- Guest contact lookup index (name + phone on active bookings)
-- Depends on: bookings table with customer_name, customer_phone, is_archived, deleted_at

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

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
  'idx_bookings_contact_lookup',
  'CREATE INDEX idx_bookings_contact_lookup ON bookings (customer_name, customer_phone, is_archived, deleted_at)'
);

DROP PROCEDURE IF EXISTS sp_add_index_if_missing;
