-- Vehicle type match tiers for SEDAN/SUV/VAN upward-compatible call matching.
-- VIP_SUV / VIP_VAN / LUXURY keep NULL match_tier → exact vehicle_type match only.
-- Do NOT reuse sort_order: it is UI order and interleaves VIP between SUV and VAN.
-- Depends on: 03_fleet_places.sql

USE ttaxi;

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

SET @col_exists = (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'vehicle_types'
    AND COLUMN_NAME = 'match_tier'
);
SET @sql = IF(
  @col_exists = 0,
  'ALTER TABLE vehicle_types ADD COLUMN match_tier TINYINT UNSIGNED NULL DEFAULT NULL COMMENT ''Hierarchy tier for SEDAN/SUV/VAN compatible matching; NULL = exact match only'' AFTER sort_order',
  'SELECT 1'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

UPDATE vehicle_types SET match_tier = 1 WHERE code = 'SEDAN' AND deleted_at IS NULL;
UPDATE vehicle_types SET match_tier = 2 WHERE code = 'SUV' AND deleted_at IS NULL;
UPDATE vehicle_types SET match_tier = 3 WHERE code = 'VAN' AND deleted_at IS NULL;
UPDATE vehicle_types
SET match_tier = NULL
WHERE code IN ('VIP_SUV', 'VIP_VAN', 'LUXURY')
  AND deleted_at IS NULL;
