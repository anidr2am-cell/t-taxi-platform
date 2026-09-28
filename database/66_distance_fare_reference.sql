-- Reference coordinates for distance-adjusted fares.
-- These city-centre anchors give each configured fare-table route a 10 km
-- included area before 100 THB increments are applied per additional 10 km.

USE ttaxi;

ALTER TABLE booking_charge_items
  MODIFY COLUMN charge_type ENUM(
    'VEHICLE_BASE', 'DISTANCE_SURCHARGE', 'NAME_SIGN', 'NIGHT_SURCHARGE',
    'AIRPORT_SURCHARGE', 'TOLL_GATE', 'PROMOTION', 'COUPON', 'MILEAGE',
    'DRIVER_EXTRA', 'SEASON_SURCHARGE', 'HOLIDAY_SURCHARGE',
    'WAITING_CHARGE', 'OTHER'
  ) NOT NULL;

UPDATE locations
SET
  latitude = CASE code
    WHEN 'PATTAYA' THEN 12.9236000
    WHEN 'BANGKOK' THEN 13.7563000
    WHEN 'HUA_HIN' THEN 12.5684000
    WHEN 'RAYONG' THEN 12.6814000
    WHEN 'AYUTTHAYA' THEN 14.3532000
    ELSE latitude
  END,
  longitude = CASE code
    WHEN 'PATTAYA' THEN 100.8825000
    WHEN 'BANGKOK' THEN 100.5018000
    WHEN 'HUA_HIN' THEN 99.9577000
    WHEN 'RAYONG' THEN 101.2816000
    WHEN 'AYUTTHAYA' THEN 100.5689000
    ELSE longitude
  END
WHERE deleted_at IS NULL
  AND code IN ('PATTAYA', 'BANGKOK', 'HUA_HIN', 'RAYONG', 'AYUTTHAYA');
