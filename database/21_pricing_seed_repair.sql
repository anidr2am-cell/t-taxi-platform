-- TTaxi Platform - MVP pricing seed repair (MySQL 8)
-- Ensures configured BKK <-> PATTAYA airport routes exist after
-- partial or older staging migrations. Does not create arbitrary fallbacks.
--   AIRPORT_PICKUP:  BKK -> PATTAYA
--   AIRPORT_DROPOFF: PATTAYA -> BKK

USE `ttaxi`;

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- Required airport and pricing locations
-- ---------------------------------------------------------------------------
INSERT INTO airports (iata_code, icao_code, country_code, city, name, timezone, is_active, deleted_at)
VALUES ('BKK', 'VTBS', 'TH', 'Bangkok', 'Suvarnabhumi Airport', 'Asia/Bangkok', 1, NULL)
ON DUPLICATE KEY UPDATE
  icao_code = VALUES(icao_code),
  country_code = VALUES(country_code),
  city = VALUES(city),
  name = VALUES(name),
  timezone = VALUES(timezone),
  is_active = 1,
  deleted_at = NULL;

INSERT INTO locations (code, type, display_name, airport_id, is_active, deleted_at)
SELECT 'BKK', 'AIRPORT', 'Suvarnabhumi Airport', a.id, 1, NULL
FROM airports a
WHERE a.iata_code = 'BKK' AND a.deleted_at IS NULL
ON DUPLICATE KEY UPDATE
  type = VALUES(type),
  display_name = VALUES(display_name),
  airport_id = VALUES(airport_id),
  is_active = 1,
  deleted_at = NULL;

-- Keep coordinates in sync for BKK airport location (no Place ID invention).
-- Sync: frontend/lib/features/booking/models/thailand_registered_airports.dart
UPDATE locations
SET
  latitude = 13.6899990,
  longitude = 100.7479240,
  display_name = 'Suvarnabhumi Airport',
  is_active = 1,
  deleted_at = NULL
WHERE code = 'BKK'
  AND type = 'AIRPORT'
  AND deleted_at IS NULL;

INSERT INTO locations (code, type, display_name, is_active, deleted_at)
VALUES ('PATTAYA', 'CITY', 'Pattaya', 1, NULL)
ON DUPLICATE KEY UPDATE
  type = VALUES(type),
  display_name = VALUES(display_name),
  is_active = 1,
  deleted_at = NULL;

-- ---------------------------------------------------------------------------
-- Required route: AIRPORT_PICKUP / BKK -> PATTAYA
-- ---------------------------------------------------------------------------
INSERT INTO routes (
  service_type_id, origin_location_id, destination_location_id,
  is_active, display_order, deleted_at
)
SELECT st.id, lo.id, ld.id, 1, 1, NULL
FROM service_types st
INNER JOIN locations lo ON lo.code = 'BKK' AND lo.deleted_at IS NULL
INNER JOIN locations ld ON ld.code = 'PATTAYA' AND ld.deleted_at IS NULL
WHERE st.code = 'AIRPORT_PICKUP' AND st.deleted_at IS NULL
ON DUPLICATE KEY UPDATE
  is_active = 1,
  display_order = VALUES(display_order),
  deleted_at = NULL;

-- ---------------------------------------------------------------------------
-- Required route: AIRPORT_DROPOFF / PATTAYA -> BKK
-- ---------------------------------------------------------------------------
INSERT INTO routes (
  service_type_id, origin_location_id, destination_location_id,
  is_active, display_order, deleted_at
)
SELECT st.id, lo.id, ld.id, 1, 2, NULL
FROM service_types st
INNER JOIN locations lo ON lo.code = 'PATTAYA' AND lo.deleted_at IS NULL
INNER JOIN locations ld ON ld.code = 'BKK' AND ld.deleted_at IS NULL
WHERE st.code = 'AIRPORT_DROPOFF' AND st.deleted_at IS NULL
ON DUPLICATE KEY UPDATE
  is_active = 1,
  display_order = VALUES(display_order),
  deleted_at = NULL;

-- ---------------------------------------------------------------------------
-- Required vehicle prices for AIRPORT_PICKUP (BKK -> PATTAYA)
-- ---------------------------------------------------------------------------
INSERT INTO vehicle_prices (route_id, vehicle_type_id, price, currency, is_active, deleted_at)
SELECT r.id, vt.id, seed.price, 'THB', 1, NULL
FROM routes r
INNER JOIN service_types st ON st.id = r.service_type_id AND st.code = 'AIRPORT_PICKUP'
INNER JOIN locations lo ON lo.id = r.origin_location_id AND lo.code = 'BKK'
INNER JOIN locations ld ON ld.id = r.destination_location_id AND ld.code = 'PATTAYA'
CROSS JOIN (
  SELECT 'SEDAN' AS vehicle_code, 800.00 AS price
  UNION ALL SELECT 'SUV', 1000.00
  UNION ALL SELECT 'VIP_SUV', 1200.00
  UNION ALL SELECT 'VAN', 1500.00
  UNION ALL SELECT 'VIP_VAN', 1800.00
  UNION ALL SELECT 'LUXURY', 2000.00
) seed
INNER JOIN vehicle_types vt ON vt.code = seed.vehicle_code AND vt.deleted_at IS NULL
WHERE r.deleted_at IS NULL
ON DUPLICATE KEY UPDATE
  is_active = 1,
  deleted_at = NULL;

-- ---------------------------------------------------------------------------
-- Required vehicle prices for AIRPORT_DROPOFF (PATTAYA -> BKK)
-- ---------------------------------------------------------------------------
INSERT INTO vehicle_prices (route_id, vehicle_type_id, price, currency, is_active, deleted_at)
SELECT r.id, vt.id, seed.price, 'THB', 1, NULL
FROM routes r
INNER JOIN service_types st ON st.id = r.service_type_id AND st.code = 'AIRPORT_DROPOFF'
INNER JOIN locations lo ON lo.id = r.origin_location_id AND lo.code = 'PATTAYA'
INNER JOIN locations ld ON ld.id = r.destination_location_id AND ld.code = 'BKK'
CROSS JOIN (
  SELECT 'SEDAN' AS vehicle_code, 800.00 AS price
  UNION ALL SELECT 'SUV', 1000.00
  UNION ALL SELECT 'VIP_SUV', 1200.00
  UNION ALL SELECT 'VAN', 1500.00
  UNION ALL SELECT 'VIP_VAN', 1800.00
  UNION ALL SELECT 'LUXURY', 2000.00
) seed
INNER JOIN vehicle_types vt ON vt.code = seed.vehicle_code AND vt.deleted_at IS NULL
WHERE r.deleted_at IS NULL
ON DUPLICATE KEY UPDATE
  is_active = 1,
  deleted_at = NULL;
