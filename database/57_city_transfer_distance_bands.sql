-- CITY_TRANSFER distance-band pricing (Stage 1).
-- Depends on: 15_pricing_architecture.sql
-- Additive + rerunnable.

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

SET @city_transfer_distance_bands_exists = (
  SELECT COUNT(*)
  FROM information_schema.TABLES
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'city_transfer_distance_bands'
);

SET @create_city_transfer_distance_bands_sql = IF(
  @city_transfer_distance_bands_exists = 0,
  'CREATE TABLE city_transfer_distance_bands (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT,
    min_km DECIMAL(8, 2) NOT NULL,
    max_km DECIMAL(8, 2) NULL DEFAULT NULL,
    sedan_price DECIMAL(12, 2) NULL DEFAULT NULL,
    suv_price DECIMAL(12, 2) NULL DEFAULT NULL,
    van_price DECIMAL(12, 2) NULL DEFAULT NULL,
    currency CHAR(3) NOT NULL DEFAULT ''THB'',
    is_active TINYINT(1) NOT NULL DEFAULT 1,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uk_city_transfer_distance_bands_range (min_km, max_km),
    KEY idx_city_transfer_distance_bands_active (is_active, min_km)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci',
  'SELECT 1'
);

PREPARE create_city_transfer_distance_bands_stmt FROM @create_city_transfer_distance_bands_sql;
EXECUTE create_city_transfer_distance_bands_stmt;
DEALLOCATE PREPARE create_city_transfer_distance_bands_stmt;

INSERT INTO city_transfer_distance_bands (
  min_km, max_km, sedan_price, suv_price, van_price, currency, is_active
)
SELECT 0, 12, NULL, NULL, NULL, 'THB', 1
WHERE NOT EXISTS (
  SELECT 1 FROM city_transfer_distance_bands WHERE min_km = 0 AND max_km = 12
);

INSERT INTO city_transfer_distance_bands (
  min_km, max_km, sedan_price, suv_price, van_price, currency, is_active
)
SELECT 13, 50, 900, 1100, 1400, 'THB', 1
WHERE NOT EXISTS (
  SELECT 1 FROM city_transfer_distance_bands WHERE min_km = 13 AND max_km = 50
);

INSERT INTO city_transfer_distance_bands (
  min_km, max_km, sedan_price, suv_price, van_price, currency, is_active
)
SELECT 51, 100, 1100, 1350, 1700, 'THB', 1
WHERE NOT EXISTS (
  SELECT 1 FROM city_transfer_distance_bands WHERE min_km = 51 AND max_km = 100
);

INSERT INTO city_transfer_distance_bands (
  min_km, max_km, sedan_price, suv_price, van_price, currency, is_active
)
SELECT 101, 145, 1300, 1600, 2000, 'THB', 1
WHERE NOT EXISTS (
  SELECT 1 FROM city_transfer_distance_bands WHERE min_km = 101 AND max_km = 145
);

INSERT INTO city_transfer_distance_bands (
  min_km, max_km, sedan_price, suv_price, van_price, currency, is_active
)
SELECT 146, 200, 1400, 1700, 2100, 'THB', 1
WHERE NOT EXISTS (
  SELECT 1 FROM city_transfer_distance_bands WHERE min_km = 146 AND max_km = 200
);
