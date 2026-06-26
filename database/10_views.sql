-- TTaxi Platform — Read-optimized views (MySQL 8)
-- Depends on: 00_database.sql through 09_indexes.sql

USE ttaxi;

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- v_active_driver_assignments
-- Current active driver assignment per booking
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_active_driver_assignments AS
SELECT
  bda.id AS assignment_id,
  bda.booking_id,
  b.booking_number,
  bda.driver_id,
  d.name AS driver_name,
  d.phone AS driver_phone,
  d.status AS driver_status,
  d.is_online AS driver_is_online,
  bda.driver_vehicle_id,
  dv.plate_number,
  bda.status AS assignment_status,
  bda.assigned_at,
  bda.accepted_at
FROM booking_driver_assignments bda
INNER JOIN bookings b ON b.id = bda.booking_id AND b.deleted_at IS NULL
INNER JOIN drivers d ON d.id = bda.driver_id AND d.deleted_at IS NULL
LEFT JOIN driver_vehicles dv ON dv.id = bda.driver_vehicle_id AND dv.deleted_at IS NULL
WHERE bda.is_active = 1
  AND bda.deleted_at IS NULL;

-- ---------------------------------------------------------------------------
-- v_booking_charge_summary
-- Charge line totals grouped by booking
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_booking_charge_summary AS
SELECT
  bci.booking_id,
  b.booking_number,
  bci.charge_type,
  COUNT(*) AS line_count,
  SUM(bci.amount) AS total_amount,
  b.currency
FROM booking_charge_items bci
INNER JOIN bookings b ON b.id = bci.booking_id AND b.deleted_at IS NULL
WHERE bci.deleted_at IS NULL
GROUP BY bci.booking_id, b.booking_number, bci.charge_type, b.currency;

-- ---------------------------------------------------------------------------
-- v_dispatch_board
-- Kanban cards for admin dispatch board (today-focused filter in app layer)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_dispatch_board AS
SELECT
  b.id AS booking_id,
  b.booking_number,
  b.status,
  b.scheduled_pickup_at,
  b.service_type_id,
  st.code AS service_type_code,
  b.origin_address,
  b.destination_address,
  b.vehicle_type_id,
  vt.code AS vehicle_type_code,
  b.vehicle_count,
  b.total_amount,
  b.currency,
  b.driver_id,
  d.name AS driver_name,
  bp.adults,
  bp.children,
  bp.infants,
  bl.carriers_20_inch,
  bl.carriers_24_inch_plus,
  bl.golf_bags,
  btd.flight_number,
  btd.flight_scheduled_arrival_at,
  btd.flight_estimated_arrival_at,
  btd.delay_minutes,
  btd.delay_status,
  b.created_at
FROM bookings b
INNER JOIN service_types st ON st.id = b.service_type_id AND st.deleted_at IS NULL
INNER JOIN vehicle_types vt ON vt.id = b.vehicle_type_id AND vt.deleted_at IS NULL
LEFT JOIN drivers d ON d.id = b.driver_id AND d.deleted_at IS NULL
LEFT JOIN booking_passengers bp ON bp.booking_id = b.id AND bp.deleted_at IS NULL
LEFT JOIN booking_luggage bl ON bl.booking_id = b.id AND bl.deleted_at IS NULL
LEFT JOIN booking_transfer_details btd ON btd.booking_id = b.id AND btd.deleted_at IS NULL
WHERE b.deleted_at IS NULL;

-- ---------------------------------------------------------------------------
-- v_flight_monitor
-- Airport pickup bookings with flight tracking fields
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_flight_monitor AS
SELECT
  b.id AS booking_id,
  b.booking_number,
  b.status,
  b.scheduled_pickup_at,
  b.driver_id,
  d.name AS driver_name,
  d.phone AS driver_phone,
  btd.flight_number,
  a.iata_code AS airport_iata,
  a.name AS airport_name,
  btd.flight_scheduled_arrival_at,
  btd.flight_estimated_arrival_at,
  btd.delay_minutes,
  btd.delay_status,
  btd.flight_raw_data
FROM bookings b
INNER JOIN service_types st ON st.id = b.service_type_id AND st.deleted_at IS NULL
INNER JOIN booking_transfer_details btd ON btd.booking_id = b.id AND btd.deleted_at IS NULL
LEFT JOIN airports a ON a.id = btd.airport_id AND a.deleted_at IS NULL
LEFT JOIN drivers d ON d.id = b.driver_id AND d.deleted_at IS NULL
WHERE b.deleted_at IS NULL
  AND st.code IN ('AIRPORT_PICKUP', 'AIRPORT_DROPOFF')
  AND btd.flight_number IS NOT NULL;
