-- Coupon templates and issued-coupon image snapshots.
-- Depends on: 58_customer_coupons.sql
-- Additive + rerunnable.

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

SET @coupon_templates_exists = (
  SELECT COUNT(*)
  FROM information_schema.TABLES
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'coupon_templates'
);

SET @create_coupon_templates_sql = IF(
  @coupon_templates_exists = 0,
  'CREATE TABLE coupon_templates (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    title VARCHAR(255) NOT NULL,
    discount_amount INT NOT NULL,
    image_path VARCHAR(500) NOT NULL,
    is_active TINYINT(1) NOT NULL DEFAULT 1,
    created_by_admin_id BIGINT UNSIGNED NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_coupon_templates_active (is_active),
    CONSTRAINT fk_coupon_templates_created_by_admin_id
      FOREIGN KEY (created_by_admin_id) REFERENCES users (id)
      ON DELETE SET NULL ON UPDATE CASCADE
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci',
  'SELECT 1'
);

PREPARE create_coupon_templates_stmt FROM @create_coupon_templates_sql;
EXECUTE create_coupon_templates_stmt;
DEALLOCATE PREPARE create_coupon_templates_stmt;

SET @customer_coupons_template_id_exists = (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'customer_coupons'
    AND COLUMN_NAME = 'template_id'
);

SET @add_customer_coupons_template_id_sql = IF(
  @customer_coupons_template_id_exists = 0,
  'ALTER TABLE customer_coupons
    ADD COLUMN template_id BIGINT UNSIGNED NULL AFTER discount_amount',
  'SELECT 1'
);

PREPARE add_customer_coupons_template_id_stmt FROM @add_customer_coupons_template_id_sql;
EXECUTE add_customer_coupons_template_id_stmt;
DEALLOCATE PREPARE add_customer_coupons_template_id_stmt;

SET @customer_coupons_image_path_exists = (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'customer_coupons'
    AND COLUMN_NAME = 'image_path'
);

SET @add_customer_coupons_image_path_sql = IF(
  @customer_coupons_image_path_exists = 0,
  'ALTER TABLE customer_coupons
    ADD COLUMN image_path VARCHAR(500) NULL AFTER template_id',
  'SELECT 1'
);

PREPARE add_customer_coupons_image_path_stmt FROM @add_customer_coupons_image_path_sql;
EXECUTE add_customer_coupons_image_path_stmt;
DEALLOCATE PREPARE add_customer_coupons_image_path_stmt;

SET @fk_customer_coupons_template_exists = (
  SELECT COUNT(*)
  FROM information_schema.TABLE_CONSTRAINTS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'customer_coupons'
    AND CONSTRAINT_NAME = 'fk_customer_coupons_template'
    AND CONSTRAINT_TYPE = 'FOREIGN KEY'
);

SET @add_fk_customer_coupons_template_sql = IF(
  @fk_customer_coupons_template_exists = 0,
  'ALTER TABLE customer_coupons
    ADD CONSTRAINT fk_customer_coupons_template
      FOREIGN KEY (template_id) REFERENCES coupon_templates (id)
      ON DELETE SET NULL ON UPDATE CASCADE',
  'SELECT 1'
);

PREPARE add_fk_customer_coupons_template_stmt FROM @add_fk_customer_coupons_template_sql;
EXECUTE add_fk_customer_coupons_template_stmt;
DEALLOCATE PREPARE add_fk_customer_coupons_template_stmt;
