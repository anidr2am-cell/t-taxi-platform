-- Post-migration checks for 65_migrate_vip_van_to_van.sql (run on tride_staging).
-- Expect: zero driver_vehicles / drivers still on VIP_VAN; VAN drivers match VAN OPEN bookings.

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

SELECT 'driver_vehicles_still_vip_van' AS check_name, COUNT(*) AS cnt
FROM driver_vehicles dv
INNER JOIN vehicle_types vt ON vt.id = dv.vehicle_type_id AND vt.code = 'VIP_VAN'
WHERE dv.deleted_at IS NULL;

SELECT 'drivers_primary_still_vip_van' AS check_name, COUNT(*) AS cnt
FROM drivers d
INNER JOIN vehicle_types vt ON vt.id = d.primary_vehicle_type_id AND vt.code = 'VIP_VAN';

SELECT 'pending_applications_still_vip_van' AS check_name, COUNT(*) AS cnt
FROM driver_applications
WHERE vehicle_type_code = 'VIP_VAN' AND deleted_at IS NULL;

-- Sample: VAN-approved drivers who would see at least one OPEN VAN booking (vehicle match SQL path).
SELECT d.id AS driver_id, d.user_id, u.email, COUNT(DISTINCT b.id) AS open_van_bookings_visible
FROM drivers d
INNER JOIN users u ON u.id = d.user_id AND u.deleted_at IS NULL AND u.is_active = 1
INNER JOIN driver_vehicles dv ON dv.driver_id = d.id AND dv.deleted_at IS NULL
  AND dv.approval_status = 'APPROVED' AND dv.is_active = 1
INNER JOIN vehicle_types vt_driver ON vt_driver.id = dv.vehicle_type_id AND vt_driver.code = 'VAN'
INNER JOIN bookings b ON b.deleted_at IS NULL AND b.is_archived = 0 AND b.status = 'OPEN'
INNER JOIN vehicle_types vt_booking ON vt_booking.id = b.vehicle_type_id AND vt_booking.code = 'VAN'
WHERE d.deleted_at IS NULL AND d.is_active = 1
  AND NOT EXISTS (
    SELECT 1 FROM booking_driver_assignments bda
    WHERE bda.booking_id = b.id AND bda.is_active = 1 AND bda.deleted_at IS NULL
  )
  AND (
    dv.vehicle_type_id = b.vehicle_type_id
    OR (
      vt_driver.match_tier IS NOT NULL AND vt_booking.match_tier IS NOT NULL
      AND vt_driver.match_tier >= vt_booking.match_tier
    )
  )
GROUP BY d.id, d.user_id, u.email
ORDER BY open_van_bookings_visible DESC
LIMIT 20;
