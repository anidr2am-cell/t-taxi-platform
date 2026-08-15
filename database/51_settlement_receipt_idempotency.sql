-- Settlement receipt upload idempotency (scoped per booking + driver + key).
-- Depends on: 04_booking_core.sql, 16_booking_qr_settlement.sql
-- Additive + rerunnable.

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

SET @settlement_receipt_idempotency_exists = (
  SELECT COUNT(*)
  FROM information_schema.TABLES
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'settlement_receipt_idempotency'
);

SET @create_settlement_receipt_idempotency_sql = IF(
  @settlement_receipt_idempotency_exists = 0,
  'CREATE TABLE settlement_receipt_idempotency (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    booking_id BIGINT UNSIGNED NOT NULL,
    driver_user_id BIGINT UNSIGNED NOT NULL,
    idempotency_key VARCHAR(128) NOT NULL,
    request_fingerprint CHAR(64) NOT NULL,
    status ENUM(''PENDING'', ''COMPLETED'') NOT NULL DEFAULT ''PENDING'',
    receipt_file_id BIGINT UNSIGNED NULL DEFAULT NULL,
    response_status SMALLINT UNSIGNED NOT NULL DEFAULT 200,
    response_payload JSON NULL DEFAULT NULL,
    expires_at DATETIME NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uk_settlement_receipt_idempotency_scope (
      booking_id,
      driver_user_id,
      idempotency_key
    ),
    KEY idx_settlement_receipt_idempotency_expires (expires_at),
    CONSTRAINT fk_settlement_receipt_idempotency_booking_id
      FOREIGN KEY (booking_id) REFERENCES bookings (id)
      ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_settlement_receipt_idempotency_driver_user_id
      FOREIGN KEY (driver_user_id) REFERENCES users (id)
      ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_settlement_receipt_idempotency_receipt_file_id
      FOREIGN KEY (receipt_file_id) REFERENCES files (id)
      ON DELETE SET NULL ON UPDATE CASCADE
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci',
  'SELECT 1'
);

PREPARE create_settlement_receipt_idempotency_stmt FROM @create_settlement_receipt_idempotency_sql;
EXECUTE create_settlement_receipt_idempotency_stmt;
DEALLOCATE PREPARE create_settlement_receipt_idempotency_stmt;
