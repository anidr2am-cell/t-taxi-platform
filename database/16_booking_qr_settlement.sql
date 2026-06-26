-- TTaxi Platform — Booking QR verification & commission settlement prep
-- Depends on: 04_booking_core.sql through 15_pricing_architecture.sql

USE ttaxi;

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

SET @payment_method_exists = (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'bookings'
    AND COLUMN_NAME = 'payment_method'
);

SET @add_payment_method_sql = IF(
  @payment_method_exists = 0,
  'ALTER TABLE bookings ADD COLUMN payment_method ENUM(''PAY_DRIVER'', ''ONLINE'') NOT NULL DEFAULT ''PAY_DRIVER'' AFTER payment_status',
  'SELECT 1'
);
PREPARE stmt_payment_method FROM @add_payment_method_sql;
EXECUTE stmt_payment_method;
DEALLOCATE PREPARE stmt_payment_method;

SET @commission_status_exists = (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'bookings'
    AND COLUMN_NAME = 'commission_status'
);

SET @add_commission_sql = IF(
  @commission_status_exists = 0,
  'ALTER TABLE bookings ADD COLUMN commission_status ENUM(''NOT_DUE_YET'', ''PENDING_AFTER_COMPLETION'', ''DUE'', ''OVERDUE'', ''PAID'', ''WAIVED'') NOT NULL DEFAULT ''NOT_DUE_YET'' AFTER payment_method',
  'SELECT 1'
);
PREPARE stmt_commission FROM @add_commission_sql;
EXECUTE stmt_commission;
DEALLOCATE PREPARE stmt_commission;

SET @commission_amount_exists = (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'bookings'
    AND COLUMN_NAME = 'commission_amount'
);

SET @add_commission_amount_sql = IF(
  @commission_amount_exists = 0,
  'ALTER TABLE bookings ADD COLUMN commission_amount DECIMAL(12, 2) NULL DEFAULT NULL AFTER commission_status',
  'SELECT 1'
);
PREPARE stmt_commission_amount FROM @add_commission_amount_sql;
EXECUTE stmt_commission_amount;
DEALLOCATE PREPARE stmt_commission_amount;

SET @commission_due_exists = (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'bookings'
    AND COLUMN_NAME = 'commission_due_at'
);

SET @add_commission_due_sql = IF(
  @commission_due_exists = 0,
  'ALTER TABLE bookings ADD COLUMN commission_due_at DATETIME NULL DEFAULT NULL AFTER commission_amount',
  'SELECT 1'
);
PREPARE stmt_commission_due FROM @add_commission_due_sql;
EXECUTE stmt_commission_due;
DEALLOCATE PREPARE stmt_commission_due;

SET @commission_paid_exists = (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'bookings'
    AND COLUMN_NAME = 'commission_paid_at'
);

SET @add_commission_paid_sql = IF(
  @commission_paid_exists = 0,
  'ALTER TABLE bookings ADD COLUMN commission_paid_at DATETIME NULL DEFAULT NULL AFTER commission_due_at',
  'SELECT 1'
);
PREPARE stmt_commission_paid FROM @add_commission_paid_sql;
EXECUTE stmt_commission_paid;
DEALLOCATE PREPARE stmt_commission_paid;

SET @commission_receipt_exists = (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'bookings'
    AND COLUMN_NAME = 'commission_receipt_file_id'
);

SET @add_commission_receipt_sql = IF(
  @commission_receipt_exists = 0,
  'ALTER TABLE bookings ADD COLUMN commission_receipt_file_id BIGINT UNSIGNED NULL DEFAULT NULL AFTER commission_paid_at',
  'SELECT 1'
);
PREPARE stmt_commission_receipt FROM @add_commission_receipt_sql;
EXECUTE stmt_commission_receipt;
DEALLOCATE PREPARE stmt_commission_receipt;

SET @boarding_hash_exists = (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'bookings'
    AND COLUMN_NAME = 'boarding_qr_token_hash'
);

SET @add_boarding_hash_sql = IF(
  @boarding_hash_exists = 0,
  'ALTER TABLE bookings ADD COLUMN boarding_qr_token_hash CHAR(64) NULL DEFAULT NULL AFTER metadata',
  'SELECT 1'
);
PREPARE stmt_boarding_hash FROM @add_boarding_hash_sql;
EXECUTE stmt_boarding_hash;
DEALLOCATE PREPARE stmt_boarding_hash;

SET @boarding_expires_exists = (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'bookings'
    AND COLUMN_NAME = 'boarding_qr_expires_at'
);

SET @add_boarding_expires_sql = IF(
  @boarding_expires_exists = 0,
  'ALTER TABLE bookings ADD COLUMN boarding_qr_expires_at DATETIME NULL DEFAULT NULL AFTER boarding_qr_token_hash',
  'SELECT 1'
);
PREPARE stmt_boarding_expires FROM @add_boarding_expires_sql;
EXECUTE stmt_boarding_expires;
DEALLOCATE PREPARE stmt_boarding_expires;

SET @boarding_used_exists = (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'bookings'
    AND COLUMN_NAME = 'boarding_qr_used_at'
);

SET @add_boarding_used_sql = IF(
  @boarding_used_exists = 0,
  'ALTER TABLE bookings ADD COLUMN boarding_qr_used_at DATETIME NULL DEFAULT NULL AFTER boarding_qr_expires_at',
  'SELECT 1'
);
PREPARE stmt_boarding_used FROM @add_boarding_used_sql;
EXECUTE stmt_boarding_used;
DEALLOCATE PREPARE stmt_boarding_used;

SET @dropoff_hash_exists = (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'bookings'
    AND COLUMN_NAME = 'dropoff_qr_token_hash'
);

SET @add_dropoff_hash_sql = IF(
  @dropoff_hash_exists = 0,
  'ALTER TABLE bookings ADD COLUMN dropoff_qr_token_hash CHAR(64) NULL DEFAULT NULL AFTER boarding_qr_used_at',
  'SELECT 1'
);
PREPARE stmt_dropoff_hash FROM @add_dropoff_hash_sql;
EXECUTE stmt_dropoff_hash;
DEALLOCATE PREPARE stmt_dropoff_hash;

SET @dropoff_expires_exists = (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'bookings'
    AND COLUMN_NAME = 'dropoff_qr_expires_at'
);

SET @add_dropoff_expires_sql = IF(
  @dropoff_expires_exists = 0,
  'ALTER TABLE bookings ADD COLUMN dropoff_qr_expires_at DATETIME NULL DEFAULT NULL AFTER dropoff_qr_token_hash',
  'SELECT 1'
);
PREPARE stmt_dropoff_expires FROM @add_dropoff_expires_sql;
EXECUTE stmt_dropoff_expires;
DEALLOCATE PREPARE stmt_dropoff_expires;

SET @dropoff_used_exists = (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'bookings'
    AND COLUMN_NAME = 'dropoff_qr_used_at'
);

SET @add_dropoff_used_sql = IF(
  @dropoff_used_exists = 0,
  'ALTER TABLE bookings ADD COLUMN dropoff_qr_used_at DATETIME NULL DEFAULT NULL AFTER dropoff_qr_expires_at',
  'SELECT 1'
);
PREPARE stmt_dropoff_used FROM @add_dropoff_used_sql;
EXECUTE stmt_dropoff_used;
DEALLOCATE PREPARE stmt_dropoff_used;

SET @commission_receipt_fk_exists = (
  SELECT COUNT(*)
  FROM information_schema.TABLE_CONSTRAINTS
  WHERE CONSTRAINT_SCHEMA = DATABASE()
    AND TABLE_NAME = 'bookings'
    AND CONSTRAINT_NAME = 'fk_bookings_commission_receipt_file_id'
    AND CONSTRAINT_TYPE = 'FOREIGN KEY'
);

SET @add_commission_receipt_fk_sql = IF(
  @commission_receipt_fk_exists = 0,
  'ALTER TABLE bookings ADD CONSTRAINT fk_bookings_commission_receipt_file_id FOREIGN KEY (commission_receipt_file_id) REFERENCES files (id) ON DELETE SET NULL ON UPDATE CASCADE',
  'SELECT 1'
);
PREPARE stmt_commission_receipt_fk FROM @add_commission_receipt_fk_sql;
EXECUTE stmt_commission_receipt_fk;
DEALLOCATE PREPARE stmt_commission_receipt_fk;
