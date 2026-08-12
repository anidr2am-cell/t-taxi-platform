-- Booking create idempotency keys (additive, rerunnable).
-- Depends on: 04_booking_core.sql
-- TTL is enforced via expires_at; cleanup job can be added later.

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

SET @booking_idempotency_keys_table_exists = (
  SELECT COUNT(*)
  FROM information_schema.TABLES
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'booking_idempotency_keys'
);

SET @create_booking_idempotency_keys_sql = IF(
  @booking_idempotency_keys_table_exists = 0,
  'CREATE TABLE booking_idempotency_keys (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    idempotency_key VARCHAR(128) NOT NULL,
    request_hash CHAR(64) NOT NULL,
    booking_id BIGINT UNSIGNED NULL DEFAULT NULL,
    response_status SMALLINT UNSIGNED NOT NULL DEFAULT 201,
    response_payload JSON NULL DEFAULT NULL,
    status ENUM(''PENDING'', ''COMPLETED'') NOT NULL DEFAULT ''PENDING'',
    expires_at DATETIME NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uk_booking_idempotency_key (idempotency_key),
    KEY idx_booking_idempotency_expires (expires_at),
    KEY idx_booking_idempotency_booking (booking_id),
    CONSTRAINT fk_booking_idempotency_booking_id
      FOREIGN KEY (booking_id) REFERENCES bookings (id)
      ON DELETE SET NULL ON UPDATE CASCADE
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci',
  'SELECT 1'
);

PREPARE create_booking_idempotency_keys_stmt FROM @create_booking_idempotency_keys_sql;
EXECUTE create_booking_idempotency_keys_stmt;
DEALLOCATE PREPARE create_booking_idempotency_keys_stmt;
