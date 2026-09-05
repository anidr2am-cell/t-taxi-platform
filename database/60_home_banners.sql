-- Home page promotional banners for customer landing carousel.
-- Depends on: users table (created_by_admin_id FK)
-- Additive + rerunnable.

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

SET @home_banners_exists = (
  SELECT COUNT(*)
  FROM information_schema.TABLES
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'home_banners'
);

SET @create_home_banners_sql = IF(
  @home_banners_exists = 0,
  'CREATE TABLE home_banners (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    image_path VARCHAR(500) NOT NULL,
    display_order INT NOT NULL DEFAULT 0,
    is_active TINYINT(1) NOT NULL DEFAULT 1,
    created_by_admin_id BIGINT UNSIGNED NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_home_banners_active_order (is_active, display_order),
    CONSTRAINT fk_home_banners_created_by_admin_id
      FOREIGN KEY (created_by_admin_id) REFERENCES users (id)
      ON DELETE SET NULL ON UPDATE CASCADE
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci',
  'SELECT 1'
);

PREPARE create_home_banners_stmt FROM @create_home_banners_sql;
EXECUTE create_home_banners_stmt;
DEALLOCATE PREPARE create_home_banners_stmt;
