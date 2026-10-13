-- Close the CITY_TRANSFER 12.00-12.99 km pricing gap and disable the unused
-- LUXURY vehicle type plus its capacity rule. No rows are deleted.
-- Depends on: 57_city_transfer_distance_bands.sql, 65_migrate_vip_van_to_van.sql

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

START TRANSACTION;

UPDATE city_transfer_distance_bands
SET max_km = 11.99
WHERE min_km = 0.00
  AND max_km = 12.00;

UPDATE city_transfer_distance_bands
SET min_km = 12.00,
    max_km = 50.99
WHERE min_km = 13.00
  AND max_km = 50.00;

UPDATE city_transfer_distance_bands
SET max_km = 100.99
WHERE min_km = 51.00
  AND max_km = 100.00;

UPDATE city_transfer_distance_bands
SET max_km = 145.99
WHERE min_km = 101.00
  AND max_km = 145.00;

UPDATE vehicle_capacity_rules vcr
INNER JOIN vehicle_types vt ON vt.id = vcr.vehicle_type_id
SET vcr.is_active = 0
WHERE vcr.id = 6
  AND vt.code = 'LUXURY'
  AND vcr.deleted_at IS NULL;

UPDATE vehicle_types
SET is_active = 0
WHERE code = 'LUXURY'
  AND deleted_at IS NULL;

COMMIT;
