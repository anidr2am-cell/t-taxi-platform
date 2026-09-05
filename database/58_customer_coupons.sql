-- Customer coupon ledger for admin-issued discounts.
-- Depends on: 01_identity.sql, 04_booking_core.sql
-- Additive + rerunnable.

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

SET @customer_coupons_exists = (
  SELECT COUNT(*)
  FROM information_schema.TABLES
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'customer_coupons'
);

SET @create_customer_coupons_sql = IF(
  @customer_coupons_exists = 0,
  'CREATE TABLE customer_coupons (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    customer_user_id BIGINT UNSIGNED NOT NULL,
    title VARCHAR(255) NOT NULL,
    discount_amount INT NOT NULL,
    status ENUM(''AVAILABLE'', ''USED'') NOT NULL DEFAULT ''AVAILABLE'',
    issued_by_admin_id BIGINT UNSIGNED NULL,
    issued_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    used_at DATETIME NULL,
    used_booking_id BIGINT UNSIGNED NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_customer_coupons_customer_status (customer_user_id, status),
    KEY idx_customer_coupons_issued_at (issued_at),
    CONSTRAINT fk_customer_coupons_customer_user_id
      FOREIGN KEY (customer_user_id) REFERENCES users (id)
      ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_customer_coupons_issued_by_admin_id
      FOREIGN KEY (issued_by_admin_id) REFERENCES users (id)
      ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT fk_customer_coupons_used_booking_id
      FOREIGN KEY (used_booking_id) REFERENCES bookings (id)
      ON DELETE SET NULL ON UPDATE CASCADE
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci',
  'SELECT 1'
);

PREPARE create_customer_coupons_stmt FROM @create_customer_coupons_sql;
EXECUTE create_customer_coupons_stmt;
DEALLOCATE PREPARE create_customer_coupons_stmt;
