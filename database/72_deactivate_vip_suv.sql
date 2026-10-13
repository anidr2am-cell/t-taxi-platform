-- Disable the unused VIP_SUV type and capacity rule together. No rows are deleted.
SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

START TRANSACTION;

UPDATE vehicle_capacity_rules vcr
INNER JOIN vehicle_types vt ON vt.id = vcr.vehicle_type_id
SET vcr.is_active = 0
WHERE vcr.id = 3
  AND vt.id = 3
  AND vt.code = 'VIP_SUV'
  AND vcr.deleted_at IS NULL;

UPDATE vehicle_types
SET is_active = 0
WHERE id = 3
  AND code = 'VIP_SUV'
  AND deleted_at IS NULL;

COMMIT;
