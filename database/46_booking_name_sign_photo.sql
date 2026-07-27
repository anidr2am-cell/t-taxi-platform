-- TTaxi Platform -- Booking name sign photo file link
-- Depends on: 07_storage.sql, 45_booking_name_sign_text.sql
-- Rerunnable: adds column/FK only when missing.

USE ttaxi;

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

SET @name_sign_photo_col_exists = (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'bookings'
    AND COLUMN_NAME = 'name_sign_photo_file_id'
);

SET @add_name_sign_photo_col_sql = IF(
  @name_sign_photo_col_exists = 0,
  'ALTER TABLE bookings ADD COLUMN name_sign_photo_file_id BIGINT UNSIGNED NULL DEFAULT NULL AFTER name_sign_text',
  'SELECT 1'
);
PREPARE stmt_name_sign_photo_col FROM @add_name_sign_photo_col_sql;
EXECUTE stmt_name_sign_photo_col;
DEALLOCATE PREPARE stmt_name_sign_photo_col;

SET @name_sign_photo_fk_exists = (
  SELECT COUNT(*)
  FROM information_schema.TABLE_CONSTRAINTS
  WHERE CONSTRAINT_SCHEMA = DATABASE()
    AND TABLE_NAME = 'bookings'
    AND CONSTRAINT_NAME = 'fk_bookings_name_sign_photo_file_id'
    AND CONSTRAINT_TYPE = 'FOREIGN KEY'
);

SET @add_name_sign_photo_fk_sql = IF(
  @name_sign_photo_fk_exists = 0,
  'ALTER TABLE bookings ADD CONSTRAINT fk_bookings_name_sign_photo_file_id FOREIGN KEY (name_sign_photo_file_id) REFERENCES files (id) ON DELETE SET NULL ON UPDATE CASCADE',
  'SELECT 1'
);
PREPARE stmt_name_sign_photo_fk FROM @add_name_sign_photo_fk_sql;
EXECUTE stmt_name_sign_photo_fk;
DEALLOCATE PREPARE stmt_name_sign_photo_fk;
