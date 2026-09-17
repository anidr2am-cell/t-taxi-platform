-- Add REDEEM / REDEEM_REVERSAL mileage transaction types, and MILEAGE charge type.
-- Depends on: 56_customer_mileage.sql, 04_booking_core.sql, 12_schema_fixes.sql
-- Additive + rerunnable.

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

SET @mileage_type_has_redeem = (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'mileage_transactions'
    AND COLUMN_NAME = 'type'
    AND COLUMN_TYPE LIKE '%REDEEM_REVERSAL%'
);

SET @alter_mileage_type_sql = IF(
  @mileage_type_has_redeem = 0,
  'ALTER TABLE mileage_transactions
     MODIFY COLUMN type ENUM(''ACCRUE'', ''REVERSAL'', ''REDEEM'', ''REDEEM_REVERSAL'') NOT NULL',
  'SELECT 1'
);

PREPARE alter_mileage_type_stmt FROM @alter_mileage_type_sql;
EXECUTE alter_mileage_type_stmt;
DEALLOCATE PREPARE alter_mileage_type_stmt;

SET @charge_type_has_mileage = (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'booking_charge_items'
    AND COLUMN_NAME = 'charge_type'
    AND COLUMN_TYPE LIKE '%MILEAGE%'
);

SET @alter_charge_type_sql = IF(
  @charge_type_has_mileage = 0,
  'ALTER TABLE booking_charge_items
     MODIFY COLUMN charge_type ENUM(
       ''VEHICLE_BASE'', ''NAME_SIGN'', ''NIGHT_SURCHARGE'', ''AIRPORT_SURCHARGE'',
       ''TOLL_GATE'', ''PROMOTION'', ''COUPON'', ''MILEAGE'', ''DRIVER_EXTRA'',
       ''SEASON_SURCHARGE'', ''HOLIDAY_SURCHARGE'', ''WAITING_CHARGE'', ''OTHER''
     ) NOT NULL',
  'SELECT 1'
);

PREPARE alter_charge_type_stmt FROM @alter_charge_type_sql;
EXECUTE alter_charge_type_stmt;
DEALLOCATE PREPARE alter_charge_type_stmt;
