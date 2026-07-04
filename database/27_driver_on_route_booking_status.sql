-- Phase 4 driver trip flow: add ON_ROUTE booking status between assignment and arrival.
-- Depends on: 04_booking_core.sql

USE ttaxi;

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

SET @booking_status_enum = (
  SELECT COLUMN_TYPE FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'bookings'
    AND COLUMN_NAME = 'status'
);

SET @sql = IF(
  @booking_status_enum NOT LIKE '%ON_ROUTE%',
  'ALTER TABLE bookings MODIFY COLUMN status ENUM(
    ''PENDING'', ''CONFIRMED'', ''DRIVER_ASSIGNED'', ''ON_ROUTE'', ''DRIVER_ARRIVED'',
    ''PICKED_UP'', ''COMPLETED'', ''CANCELLED'', ''NO_SHOW''
  ) NOT NULL DEFAULT ''PENDING''',
  'SELECT 1'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @log_from_enum = (
  SELECT COLUMN_TYPE FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'booking_status_logs'
    AND COLUMN_NAME = 'from_status'
);

SET @sql = IF(
  @log_from_enum NOT LIKE '%ON_ROUTE%',
  'ALTER TABLE booking_status_logs MODIFY COLUMN from_status ENUM(
    ''PENDING'', ''CONFIRMED'', ''DRIVER_ASSIGNED'', ''ON_ROUTE'', ''DRIVER_ARRIVED'',
    ''PICKED_UP'', ''COMPLETED'', ''CANCELLED'', ''NO_SHOW''
  ) NULL DEFAULT NULL',
  'SELECT 1'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @log_to_enum = (
  SELECT COLUMN_TYPE FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'booking_status_logs'
    AND COLUMN_NAME = 'to_status'
);

SET @sql = IF(
  @log_to_enum NOT LIKE '%ON_ROUTE%',
  'ALTER TABLE booking_status_logs MODIFY COLUMN to_status ENUM(
    ''PENDING'', ''CONFIRMED'', ''DRIVER_ASSIGNED'', ''ON_ROUTE'', ''DRIVER_ARRIVED'',
    ''PICKED_UP'', ''COMPLETED'', ''CANCELLED'', ''NO_SHOW''
  ) NOT NULL',
  'SELECT 1'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;
