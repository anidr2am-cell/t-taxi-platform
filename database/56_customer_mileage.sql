-- Customer mileage accounts and transaction ledger (Stage 1).
-- Depends on: 01_identity.sql, 04_booking_core.sql
-- Additive + rerunnable.

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

SET @customer_mileage_accounts_exists = (
  SELECT COUNT(*)
  FROM information_schema.TABLES
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'customer_mileage_accounts'
);

SET @create_customer_mileage_accounts_sql = IF(
  @customer_mileage_accounts_exists = 0,
  'CREATE TABLE customer_mileage_accounts (
    user_id BIGINT UNSIGNED NOT NULL,
    balance INT NOT NULL DEFAULT 0,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id),
    CONSTRAINT fk_customer_mileage_accounts_user_id
      FOREIGN KEY (user_id) REFERENCES users (id)
      ON DELETE CASCADE ON UPDATE CASCADE
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci',
  'SELECT 1'
);

PREPARE create_customer_mileage_accounts_stmt FROM @create_customer_mileage_accounts_sql;
EXECUTE create_customer_mileage_accounts_stmt;
DEALLOCATE PREPARE create_customer_mileage_accounts_stmt;

SET @mileage_transactions_exists = (
  SELECT COUNT(*)
  FROM information_schema.TABLES
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'mileage_transactions'
);

SET @create_mileage_transactions_sql = IF(
  @mileage_transactions_exists = 0,
  'CREATE TABLE mileage_transactions (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    user_id BIGINT UNSIGNED NOT NULL,
    booking_id BIGINT UNSIGNED NOT NULL,
    type ENUM(''ACCRUE'', ''REVERSAL'') NOT NULL,
    amount INT NOT NULL,
    balance_after INT NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uk_mileage_transactions_booking_type (booking_id, type),
    KEY idx_mileage_transactions_user_created (user_id, created_at),
    CONSTRAINT fk_mileage_transactions_user_id
      FOREIGN KEY (user_id) REFERENCES users (id)
      ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_mileage_transactions_booking_id
      FOREIGN KEY (booking_id) REFERENCES bookings (id)
      ON DELETE CASCADE ON UPDATE CASCADE
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci',
  'SELECT 1'
);

PREPARE create_mileage_transactions_stmt FROM @create_mileage_transactions_sql;
EXECUTE create_mileage_transactions_stmt;
DEALLOCATE PREPARE create_mileage_transactions_stmt;
