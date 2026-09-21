-- Admin manual open-call bookings: booking source, commission exempt flag, ADMIN_COLLECTED payment.
-- Depends on: 04_booking_core.sql, 12_schema_fixes.sql
-- Additive + rerunnable.

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

SET @booking_source_exists = (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'bookings'
    AND COLUMN_NAME = 'booking_source'
);

SET @add_booking_source_sql = IF(
  @booking_source_exists = 0,
  'ALTER TABLE bookings
     ADD COLUMN booking_source ENUM(''CUSTOMER'', ''ADMIN_MANUAL'') NOT NULL DEFAULT ''CUSTOMER'' AFTER status',
  'SELECT 1'
);

PREPARE add_booking_source_stmt FROM @add_booking_source_sql;
EXECUTE add_booking_source_stmt;
DEALLOCATE PREPARE add_booking_source_stmt;

SET @commission_exempt_exists = (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'bookings'
    AND COLUMN_NAME = 'commission_exempt'
);

SET @add_commission_exempt_sql = IF(
  @commission_exempt_exists = 0,
  'ALTER TABLE bookings
     ADD COLUMN commission_exempt TINYINT(1) NOT NULL DEFAULT 0 AFTER commission_status',
  'SELECT 1'
);

PREPARE add_commission_exempt_stmt FROM @add_commission_exempt_sql;
EXECUTE add_commission_exempt_stmt;
DEALLOCATE PREPARE add_commission_exempt_stmt;

SET @payment_method_has_admin_collected = (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'bookings'
    AND COLUMN_NAME = 'payment_method'
    AND COLUMN_TYPE LIKE '%ADMIN_COLLECTED%'
);

SET @alter_payment_method_sql = IF(
  @payment_method_has_admin_collected = 0,
  'ALTER TABLE bookings
     MODIFY COLUMN payment_method ENUM(''PAY_DRIVER'', ''ONLINE'', ''ADMIN_COLLECTED'') NOT NULL DEFAULT ''PAY_DRIVER''',
  'SELECT 1'
);

PREPARE alter_payment_method_stmt FROM @alter_payment_method_sql;
EXECUTE alter_payment_method_stmt;
DEALLOCATE PREPARE alter_payment_method_stmt;
