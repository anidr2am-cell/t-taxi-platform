-- Retire VIP_VAN for driver registration: migrate existing driver records to VAN.
-- Depends on: 03_fleet_places.sql
-- Rerunnable: updates only rows still on VIP_VAN.

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

UPDATE driver_vehicles dv
INNER JOIN vehicle_types vt_vip
  ON vt_vip.code = 'VIP_VAN'
  AND vt_vip.deleted_at IS NULL
INNER JOIN vehicle_types vt_van
  ON vt_van.code = 'VAN'
  AND vt_van.deleted_at IS NULL
SET dv.vehicle_type_id = vt_van.id,
    dv.updated_at = CURRENT_TIMESTAMP
WHERE dv.vehicle_type_id = vt_vip.id
  AND dv.deleted_at IS NULL;

UPDATE drivers d
INNER JOIN vehicle_types vt_vip
  ON vt_vip.code = 'VIP_VAN'
  AND vt_vip.deleted_at IS NULL
INNER JOIN vehicle_types vt_van
  ON vt_van.code = 'VAN'
  AND vt_van.deleted_at IS NULL
SET d.primary_vehicle_type_id = vt_van.id,
    d.updated_at = CURRENT_TIMESTAMP
WHERE d.primary_vehicle_type_id = vt_vip.id;

UPDATE driver_applications
SET vehicle_type_code = 'VAN',
    updated_at = CURRENT_TIMESTAMP
WHERE vehicle_type_code = 'VIP_VAN'
  AND deleted_at IS NULL;
