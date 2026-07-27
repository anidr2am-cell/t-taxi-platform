-- Store the exact text to print on airport pickup name signs.
-- Rerunnable: adds the column only when it is missing.

USE ttaxi;

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

SET @col_exists = (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'bookings'
    AND COLUMN_NAME = 'name_sign_text'
);
SET @sql = IF(
  @col_exists = 0,
  'ALTER TABLE bookings ADD COLUMN name_sign_text VARCHAR(100) NULL DEFAULT NULL AFTER customer_name',
  'SELECT 1'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;
