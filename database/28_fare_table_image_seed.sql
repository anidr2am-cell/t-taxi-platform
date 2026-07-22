-- T-Ride — Fare table seed from operator image (MariaDB 10.11 / MySQL 8)
-- Idempotent upsert of routes + SEDAN/SUV/VAN prices only.
-- VIP/LUXURY prices are deactivated; routes outside the fare table are deactivated.
-- Depends on: migrations through 27_driver_on_route_booking_status.sql

USE ttaxi;

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- Locations required by fare table
-- ---------------------------------------------------------------------------
INSERT INTO airports (iata_code, icao_code, country_code, city, name, timezone, is_active, deleted_at)
VALUES
  ('BKK', 'VTBS', 'TH', 'Bangkok', 'Suvarnabhumi Airport', 'Asia/Bangkok', 1, NULL),
  ('DMK', 'VTBD', 'TH', 'Bangkok', 'Don Mueang International Airport', 'Asia/Bangkok', 1, NULL)
ON DUPLICATE KEY UPDATE
  name = VALUES(name),
  city = VALUES(city),
  timezone = VALUES(timezone),
  is_active = 1,
  deleted_at = NULL;

INSERT INTO locations (code, type, display_name, airport_id, is_active, deleted_at)
SELECT a.iata_code, 'AIRPORT', a.name, a.id, 1, NULL
FROM airports a
WHERE a.iata_code IN ('BKK', 'DMK') AND a.deleted_at IS NULL
ON DUPLICATE KEY UPDATE
  type = VALUES(type),
  display_name = VALUES(display_name),
  airport_id = VALUES(airport_id),
  is_active = 1,
  deleted_at = NULL;

-- Sync: frontend/lib/features/booking/models/thailand_registered_airports.dart
UPDATE locations
SET
  latitude = CASE code
    WHEN 'BKK' THEN 13.6899990
    WHEN 'DMK' THEN 13.9132600
    ELSE latitude
  END,
  longitude = CASE code
    WHEN 'BKK' THEN 100.7479240
    WHEN 'DMK' THEN 100.6020100
    ELSE longitude
  END
WHERE deleted_at IS NULL
  AND type = 'AIRPORT'
  AND code IN ('BKK', 'DMK');

INSERT INTO locations (code, type, display_name, is_active, deleted_at)
VALUES
  ('PATTAYA', 'CITY', 'Pattaya', 1, NULL),
  ('BANGKOK', 'CITY', 'Bangkok', 1, NULL),
  ('HUA_HIN', 'CITY', 'Hua Hin', 1, NULL),
  ('RAYONG', 'CITY', 'Rayong', 1, NULL),
  ('AYUTTHAYA', 'CITY', 'Ayutthaya', 1, NULL)
ON DUPLICATE KEY UPDATE
  type = VALUES(type),
  display_name = VALUES(display_name),
  is_active = 1,
  deleted_at = NULL;

-- ---------------------------------------------------------------------------
-- Fare table matrix (service, origin, destination, vehicle, price THB)
-- ---------------------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS tmp_fare_table_seed;
CREATE TEMPORARY TABLE tmp_fare_table_seed (
  service_code VARCHAR(30) NOT NULL,
  origin_code VARCHAR(30) NOT NULL,
  destination_code VARCHAR(30) NOT NULL,
  vehicle_code VARCHAR(20) NOT NULL,
  price DECIMAL(12, 2) NOT NULL,
  PRIMARY KEY (service_code, origin_code, destination_code, vehicle_code)
);

INSERT INTO tmp_fare_table_seed (service_code, origin_code, destination_code, vehicle_code, price) VALUES
  ('AIRPORT_PICKUP', 'BKK', 'PATTAYA', 'SEDAN', 1000.00),
  ('AIRPORT_PICKUP', 'BKK', 'PATTAYA', 'SUV', 1300.00),
  ('AIRPORT_PICKUP', 'BKK', 'PATTAYA', 'VAN', 1700.00),
  ('AIRPORT_PICKUP', 'BKK', 'BANGKOK', 'SEDAN', 550.00),
  ('AIRPORT_PICKUP', 'BKK', 'BANGKOK', 'SUV', 600.00),
  ('AIRPORT_PICKUP', 'BKK', 'BANGKOK', 'VAN', 1100.00),
  ('AIRPORT_PICKUP', 'BKK', 'HUA_HIN', 'SEDAN', 2000.00),
  ('AIRPORT_PICKUP', 'BKK', 'HUA_HIN', 'SUV', 2200.00),
  ('AIRPORT_PICKUP', 'BKK', 'HUA_HIN', 'VAN', 2700.00),
  ('AIRPORT_PICKUP', 'BKK', 'RAYONG', 'SEDAN', 1500.00),
  ('AIRPORT_PICKUP', 'BKK', 'RAYONG', 'SUV', 1700.00),
  ('AIRPORT_PICKUP', 'BKK', 'RAYONG', 'VAN', 2100.00),
  ('AIRPORT_PICKUP', 'BKK', 'AYUTTHAYA', 'SEDAN', 1200.00),
  ('AIRPORT_PICKUP', 'BKK', 'AYUTTHAYA', 'SUV', 1400.00),
  ('AIRPORT_PICKUP', 'BKK', 'AYUTTHAYA', 'VAN', 1800.00),
  ('AIRPORT_PICKUP', 'DMK', 'PATTAYA', 'SEDAN', 1400.00),
  ('AIRPORT_PICKUP', 'DMK', 'PATTAYA', 'SUV', 1600.00),
  ('AIRPORT_PICKUP', 'DMK', 'PATTAYA', 'VAN', 2200.00),
  ('AIRPORT_PICKUP', 'DMK', 'BANGKOK', 'SEDAN', 600.00),
  ('AIRPORT_PICKUP', 'DMK', 'BANGKOK', 'SUV', 800.00),
  ('AIRPORT_PICKUP', 'DMK', 'BANGKOK', 'VAN', 1200.00),
  ('AIRPORT_PICKUP', 'DMK', 'HUA_HIN', 'SEDAN', 2000.00),
  ('AIRPORT_PICKUP', 'DMK', 'HUA_HIN', 'SUV', 2200.00),
  ('AIRPORT_PICKUP', 'DMK', 'HUA_HIN', 'VAN', 2700.00),
  ('AIRPORT_PICKUP', 'DMK', 'RAYONG', 'SEDAN', 1800.00),
  ('AIRPORT_PICKUP', 'DMK', 'RAYONG', 'SUV', 2000.00),
  ('AIRPORT_PICKUP', 'DMK', 'RAYONG', 'VAN', 2500.00),
  ('AIRPORT_DROPOFF', 'PATTAYA', 'BKK', 'SEDAN', 1000.00),
  ('AIRPORT_DROPOFF', 'PATTAYA', 'BKK', 'SUV', 1300.00),
  ('AIRPORT_DROPOFF', 'PATTAYA', 'BKK', 'VAN', 1700.00),
  ('AIRPORT_DROPOFF', 'PATTAYA', 'DMK', 'SEDAN', 1400.00),
  ('AIRPORT_DROPOFF', 'PATTAYA', 'DMK', 'SUV', 1600.00),
  ('AIRPORT_DROPOFF', 'PATTAYA', 'DMK', 'VAN', 2300.00),
  ('AIRPORT_DROPOFF', 'BANGKOK', 'BKK', 'SEDAN', 700.00),
  ('AIRPORT_DROPOFF', 'BANGKOK', 'BKK', 'SUV', 800.00),
  ('AIRPORT_DROPOFF', 'BANGKOK', 'BKK', 'VAN', 1200.00),
  ('CITY_TRANSFER', 'PATTAYA', 'BANGKOK', 'SEDAN', 1300.00),
  ('CITY_TRANSFER', 'PATTAYA', 'BANGKOK', 'SUV', 1500.00),
  ('CITY_TRANSFER', 'PATTAYA', 'BANGKOK', 'VAN', 2000.00),
  ('CITY_TRANSFER', 'BANGKOK', 'PATTAYA', 'SEDAN', 1300.00),
  ('CITY_TRANSFER', 'BANGKOK', 'PATTAYA', 'SUV', 1600.00),
  ('CITY_TRANSFER', 'BANGKOK', 'PATTAYA', 'VAN', 2000.00);

DROP TEMPORARY TABLE IF EXISTS tmp_fare_table_routes;
CREATE TEMPORARY TABLE tmp_fare_table_routes AS
SELECT DISTINCT service_code, origin_code, destination_code
FROM tmp_fare_table_seed;

-- ---------------------------------------------------------------------------
-- Upsert routes in fare table
-- ---------------------------------------------------------------------------
INSERT INTO routes (
  service_type_id, origin_location_id, destination_location_id,
  is_active, display_order, deleted_at
)
SELECT st.id, lo.id, ld.id, 1, 1, NULL
FROM tmp_fare_table_routes fares
INNER JOIN service_types st ON st.code = fares.service_code AND st.deleted_at IS NULL
INNER JOIN locations lo ON lo.code = fares.origin_code AND lo.deleted_at IS NULL
INNER JOIN locations ld ON ld.code = fares.destination_code AND ld.deleted_at IS NULL
ON DUPLICATE KEY UPDATE
  is_active = 1,
  deleted_at = NULL,
  updated_at = CURRENT_TIMESTAMP;

-- ---------------------------------------------------------------------------
-- Upsert SEDAN / SUV / VAN prices
-- ---------------------------------------------------------------------------
INSERT INTO vehicle_prices (route_id, vehicle_type_id, price, currency, is_active, deleted_at)
SELECT r.id, vt.id, fares.price, 'THB', 1, NULL
FROM tmp_fare_table_seed fares
INNER JOIN service_types st ON st.code = fares.service_code AND st.deleted_at IS NULL
INNER JOIN locations lo ON lo.code = fares.origin_code AND lo.deleted_at IS NULL
INNER JOIN locations ld ON ld.code = fares.destination_code AND ld.deleted_at IS NULL
INNER JOIN routes r
  ON r.service_type_id = st.id
 AND r.origin_location_id = lo.id
 AND r.destination_location_id = ld.id
 AND r.deleted_at IS NULL
INNER JOIN vehicle_types vt ON vt.code = fares.vehicle_code AND vt.deleted_at IS NULL
ON DUPLICATE KEY UPDATE
  price = VALUES(price),
  currency = VALUES(currency),
  is_active = 1,
  deleted_at = NULL,
  updated_at = CURRENT_TIMESTAMP;

-- ---------------------------------------------------------------------------
-- Deactivate non-fare vehicle tiers (no arbitrary VIP/LUXURY pricing)
-- ---------------------------------------------------------------------------
UPDATE vehicle_prices vp
INNER JOIN routes r ON r.id = vp.route_id AND r.deleted_at IS NULL
INNER JOIN service_types st ON st.id = r.service_type_id AND st.deleted_at IS NULL
INNER JOIN vehicle_types vt ON vt.id = vp.vehicle_type_id AND vt.deleted_at IS NULL
SET vp.is_active = 0,
    vp.updated_at = CURRENT_TIMESTAMP
WHERE vp.deleted_at IS NULL
  AND st.code IN ('AIRPORT_PICKUP', 'AIRPORT_DROPOFF', 'CITY_TRANSFER')
  AND vt.code IN ('VIP_SUV', 'VIP_VAN', 'LUXURY');

-- ---------------------------------------------------------------------------
-- Deactivate routes outside fare table for core transfer services
-- ---------------------------------------------------------------------------
UPDATE routes r
INNER JOIN service_types st ON st.id = r.service_type_id AND st.deleted_at IS NULL
INNER JOIN locations lo ON lo.id = r.origin_location_id AND lo.deleted_at IS NULL
INNER JOIN locations ld ON ld.id = r.destination_location_id AND ld.deleted_at IS NULL
LEFT JOIN tmp_fare_table_routes fares
  ON fares.service_code = st.code
 AND fares.origin_code = lo.code
 AND fares.destination_code = ld.code
SET r.is_active = 0,
    r.updated_at = CURRENT_TIMESTAMP
WHERE r.deleted_at IS NULL
  AND st.code IN ('AIRPORT_PICKUP', 'AIRPORT_DROPOFF', 'CITY_TRANSFER')
  AND fares.service_code IS NULL;

DROP TEMPORARY TABLE IF EXISTS tmp_fare_table_routes;
DROP TEMPORARY TABLE IF EXISTS tmp_fare_table_seed;
