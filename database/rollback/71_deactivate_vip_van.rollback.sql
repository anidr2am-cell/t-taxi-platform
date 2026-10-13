-- Restore the VIP_VAN rows disabled by migration 71. No rows are deleted.
SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

START TRANSACTION;

UPDATE vehicle_types
SET is_active = 1
WHERE id = 5
  AND code = 'VIP_VAN'
  AND deleted_at IS NULL;

UPDATE vehicle_capacity_rules vcr
INNER JOIN vehicle_types vt ON vt.id = vcr.vehicle_type_id
SET vcr.is_active = 1
WHERE vcr.id = 5
  AND vt.id = 5
  AND vt.code = 'VIP_VAN'
  AND vcr.deleted_at IS NULL;

COMMIT;
