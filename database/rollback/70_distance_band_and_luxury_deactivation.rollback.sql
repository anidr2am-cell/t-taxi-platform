-- Roll back database/70_distance_band_and_luxury_deactivation.sql.
-- No rows are deleted by either direction.

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

START TRANSACTION;

UPDATE city_transfer_distance_bands
SET max_km = 12.00
WHERE min_km = 0.00
  AND max_km = 11.99;

UPDATE city_transfer_distance_bands
SET min_km = 13.00,
    max_km = 50.00
WHERE min_km = 12.00
  AND max_km = 50.99;

UPDATE city_transfer_distance_bands
SET max_km = 100.00
WHERE min_km = 51.00
  AND max_km = 100.99;

UPDATE city_transfer_distance_bands
SET max_km = 145.00
WHERE min_km = 101.00
  AND max_km = 145.99;

UPDATE vehicle_types
SET is_active = 1
WHERE code = 'LUXURY'
  AND deleted_at IS NULL;

UPDATE vehicle_capacity_rules vcr
INNER JOIN vehicle_types vt ON vt.id = vcr.vehicle_type_id
SET vcr.is_active = 1
WHERE vcr.id = 6
  AND vt.code = 'LUXURY'
  AND vcr.deleted_at IS NULL;

COMMIT;
