-- Booking contact connection (personal messenger MVP).
-- Depends on: 04_booking_core.sql
-- Additive + rerunnable. Existing bookings backfilled to VERIFIED.

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- bookings.contact_* snapshot columns
-- ---------------------------------------------------------------------------
SET @bookings_contact_status_exists = (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'bookings'
    AND COLUMN_NAME = 'contact_status'
);

SET @add_bookings_contact_status_sql = IF(
  @bookings_contact_status_exists = 0,
  'ALTER TABLE bookings
     ADD COLUMN contact_status ENUM(''PENDING'', ''CONFIRM_REQUESTED'', ''VERIFIED'') NOT NULL DEFAULT ''VERIFIED'' AFTER status,
     ADD COLUMN contact_channel VARCHAR(20) NULL DEFAULT NULL AFTER contact_status,
     ADD COLUMN contact_requested_at DATETIME NULL DEFAULT NULL AFTER contact_channel,
     ADD COLUMN contact_verified_at DATETIME NULL DEFAULT NULL AFTER contact_requested_at,
     ADD KEY idx_bookings_contact_status (contact_status)',
  'SELECT 1'
);

PREPARE add_bookings_contact_status_stmt FROM @add_bookings_contact_status_sql;
EXECUTE add_bookings_contact_status_stmt;
DEALLOCATE PREPARE add_bookings_contact_status_stmt;

-- Backfill: all existing rows at migration time are treated as already verified.
UPDATE bookings
SET contact_status = 'VERIFIED',
    contact_verified_at = COALESCE(contact_verified_at, created_at)
WHERE contact_status <> 'VERIFIED'
  AND created_at < UTC_TIMESTAMP();

-- ---------------------------------------------------------------------------
-- booking_contact_connections
-- ---------------------------------------------------------------------------
SET @booking_contact_connections_exists = (
  SELECT COUNT(*)
  FROM information_schema.TABLES
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'booking_contact_connections'
);

SET @create_booking_contact_connections_sql = IF(
  @booking_contact_connections_exists = 0,
  'CREATE TABLE booking_contact_connections (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    booking_id BIGINT UNSIGNED NOT NULL,
    channel ENUM(''LINE'', ''KAKAO'', ''WHATSAPP'', ''WECHAT'', ''EMAIL'') NOT NULL,
    status ENUM(''PENDING'', ''CONFIRM_REQUESTED'', ''VERIFIED'', ''CANCELLED'') NOT NULL DEFAULT ''PENDING'',
    provider_user_id VARCHAR(255) NULL DEFAULT NULL,
    external_handle VARCHAR(255) NULL DEFAULT NULL,
    customer_confirmed_at DATETIME NULL DEFAULT NULL,
    admin_verified_at DATETIME NULL DEFAULT NULL,
    admin_verified_by BIGINT UNSIGNED NULL DEFAULT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_bcc_booking (booking_id),
    KEY idx_bcc_booking_status (booking_id, status),
    CONSTRAINT fk_bcc_booking_id
      FOREIGN KEY (booking_id) REFERENCES bookings (id)
      ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_bcc_admin_verified_by
      FOREIGN KEY (admin_verified_by) REFERENCES users (id)
      ON DELETE SET NULL ON UPDATE CASCADE
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci',
  'SELECT 1'
);

PREPARE create_booking_contact_connections_stmt FROM @create_booking_contact_connections_sql;
EXECUTE create_booking_contact_connections_stmt;
DEALLOCATE PREPARE create_booking_contact_connections_stmt;
