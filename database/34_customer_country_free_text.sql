-- Allow optional free-text customer country on bookings (not limited to ISO-2).
-- Idempotent: only widens column when still CHAR(2).

USE `ttaxi`;

SET @schema := DATABASE();

SET @sql := (
  SELECT IF(
    EXISTS (
      SELECT 1
      FROM information_schema.COLUMNS
      WHERE TABLE_SCHEMA = @schema
        AND TABLE_NAME = 'bookings'
        AND COLUMN_NAME = 'customer_country_code'
        AND CHARACTER_MAXIMUM_LENGTH <= 2
    ),
    'ALTER TABLE bookings MODIFY COLUMN customer_country_code VARCHAR(100) NULL DEFAULT NULL',
    'SELECT 1'
  )
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;
