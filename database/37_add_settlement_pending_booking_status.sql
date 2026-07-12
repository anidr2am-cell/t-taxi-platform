-- Idempotent repair: ensure SETTLEMENT_PENDING exists on booking status enums.
-- Safe to re-run when migration 32 was skipped or partially applied on staging.
-- Depends on: 04_booking_core.sql, 27_driver_on_route_booking_status.sql

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

SET @booking_status_enum = (
  SELECT COLUMN_TYPE FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'bookings'
    AND COLUMN_NAME = 'status'
);

SET @sql = IF(
  @booking_status_enum IS NOT NULL
    AND @booking_status_enum NOT LIKE '%SETTLEMENT_PENDING%',
  'ALTER TABLE bookings MODIFY COLUMN status ENUM(
    ''PENDING'', ''CONFIRMED'', ''DRIVER_ASSIGNED'', ''ON_ROUTE'', ''DRIVER_ARRIVED'',
    ''PICKED_UP'', ''SETTLEMENT_PENDING'', ''COMPLETED'', ''CANCELLED'', ''NO_SHOW''
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
  @log_from_enum IS NOT NULL
    AND @log_from_enum NOT LIKE '%SETTLEMENT_PENDING%',
  'ALTER TABLE booking_status_logs MODIFY COLUMN from_status ENUM(
    ''PENDING'', ''CONFIRMED'', ''DRIVER_ASSIGNED'', ''ON_ROUTE'', ''DRIVER_ARRIVED'',
    ''PICKED_UP'', ''SETTLEMENT_PENDING'', ''COMPLETED'', ''CANCELLED'', ''NO_SHOW''
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
  @log_to_enum IS NOT NULL
    AND @log_to_enum NOT LIKE '%SETTLEMENT_PENDING%',
  'ALTER TABLE booking_status_logs MODIFY COLUMN to_status ENUM(
    ''PENDING'', ''CONFIRMED'', ''DRIVER_ASSIGNED'', ''ON_ROUTE'', ''DRIVER_ARRIVED'',
    ''PICKED_UP'', ''SETTLEMENT_PENDING'', ''COMPLETED'', ''CANCELLED'', ''NO_SHOW''
  ) NOT NULL',
  'SELECT 1'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;
