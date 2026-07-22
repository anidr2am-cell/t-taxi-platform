-- PROPOSED ops data-fix ONLY — do NOT auto-run.
-- T-Ride: fill airport location coordinates for BKK/DMK/CNX/HKT
--
-- Canonical values MUST stay in sync with:
--   frontend/lib/features/booking/models/thailand_registered_airports.dart
--
-- Safety:
--   - No schema change / no migration runner
--   - Does not invent Google Place IDs
--   - Updates only AIRPORT locations for the four registered codes
--   - Does NOT rewrite historical bookings (snapshots stay as-is)
--   - No hardcoded USE <database>; select the target DB in the client session
--
-- Coordinates (driver curb / passenger-terminal oriented):
--   BKK 13.689999, 100.747924  AOT Suvarnabhumi contact Maps embed
--   DMK 13.913260, 100.602010  AOT Don Mueang contact Maps embed
--   CNX 18.7679959, 98.968563  AOT terminal-side (OSM terminal corroboration)
--   HKT 8.105401, 98.306054    AOT intl-terminal-side (OSM terminal corroboration)
--
-- Execute manually only after operator approval.

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

START TRANSACTION;

-- ---------------------------------------------------------------------------
-- 1) Preview BEFORE change (expect exactly 4 rows)
-- ---------------------------------------------------------------------------
SELECT
  code,
  type,
  display_name,
  google_place_id,
  latitude,
  longitude,
  airport_id,
  is_active,
  deleted_at
FROM locations
WHERE deleted_at IS NULL
  AND type = 'AIRPORT'
  AND code IN ('BKK', 'DMK', 'CNX', 'HKT')
ORDER BY FIELD(code, 'BKK', 'DMK', 'CNX', 'HKT');

SELECT COUNT(*) AS airport_location_row_count
FROM locations
WHERE deleted_at IS NULL
  AND type = 'AIRPORT'
  AND code IN ('BKK', 'DMK', 'CNX', 'HKT');

-- Optional guard: abort if unexpected row count (MySQL 8+ SIGNAL).
-- Uncomment after confirming the preview COUNT is exactly 4.
-- SET @airport_location_row_count := (
--   SELECT COUNT(*) FROM locations
--   WHERE deleted_at IS NULL
--     AND type = 'AIRPORT'
--     AND code IN ('BKK', 'DMK', 'CNX', 'HKT')
-- );
-- SET @msg := CONCAT('Expected 4 airport locations, found ', @airport_location_row_count);
-- IF @airport_location_row_count <> 4 THEN
--   SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = @msg;
-- END IF;
-- Note: IF/SIGNAL blocks need a stored procedure in MySQL. Prefer checking COUNT
-- in the SQL client and STOP if not exactly 4 before running the UPDATE below.

-- ---------------------------------------------------------------------------
-- 2) Backup snapshot of previous values (operator keeps this result set)
-- ---------------------------------------------------------------------------
SELECT
  id,
  code,
  display_name,
  google_place_id,
  latitude AS previous_latitude,
  longitude AS previous_longitude,
  airport_id,
  is_active,
  updated_at
FROM locations
WHERE deleted_at IS NULL
  AND type = 'AIRPORT'
  AND code IN ('BKK', 'DMK', 'CNX', 'HKT')
ORDER BY FIELD(code, 'BKK', 'DMK', 'CNX', 'HKT');

-- ---------------------------------------------------------------------------
-- 3) Apply location master update (4 codes only)
-- ---------------------------------------------------------------------------
UPDATE locations
SET
  display_name = CASE code
    WHEN 'BKK' THEN 'Suvarnabhumi Airport'
    WHEN 'DMK' THEN 'Don Mueang International Airport'
    WHEN 'CNX' THEN 'Chiang Mai International Airport'
    WHEN 'HKT' THEN 'Phuket International Airport'
    ELSE display_name
  END,
  latitude = CASE code
    WHEN 'BKK' THEN 13.6899990
    WHEN 'DMK' THEN 13.9132600
    WHEN 'CNX' THEN 18.7679959
    WHEN 'HKT' THEN 8.1054010
    ELSE latitude
  END,
  longitude = CASE code
    WHEN 'BKK' THEN 100.7479240
    WHEN 'DMK' THEN 100.6020100
    WHEN 'CNX' THEN 98.9685630
    WHEN 'HKT' THEN 98.3060540
    ELSE longitude
  END,
  -- Keep place IDs unchanged (null until verified).
  google_place_id = google_place_id,
  is_active = 1
WHERE deleted_at IS NULL
  AND type = 'AIRPORT'
  AND code IN ('BKK', 'DMK', 'CNX', 'HKT');

-- Expect ROW_COUNT() = 4 (or fewer if a code is missing — investigate before COMMIT).
SELECT ROW_COUNT() AS updated_row_count;

-- ---------------------------------------------------------------------------
-- 4) Verification AFTER change
-- ---------------------------------------------------------------------------
SELECT
  code,
  type,
  display_name,
  google_place_id,
  latitude,
  longitude,
  airport_id,
  is_active
FROM locations
WHERE deleted_at IS NULL
  AND type = 'AIRPORT'
  AND code IN ('BKK', 'DMK', 'CNX', 'HKT')
ORDER BY FIELD(code, 'BKK', 'DMK', 'CNX', 'HKT');

-- Finish explicitly after verification:
--   COMMIT;    -- only when verification is correct
--   ROLLBACK;  -- if verification fails
-- Do not leave an open transaction unattended.

-- ---------------------------------------------------------------------------
-- BOOKINGS: preview only — DO NOT UPDATE without a separate approved plan.
-- Completed / cancelled / no-show are excluded. Customer hotel places are not
-- rewritten by matching city-only strings alone.
-- ---------------------------------------------------------------------------
-- SELECT
--   booking_number,
--   status,
--   origin_address,
--   origin_lat,
--   origin_lng,
--   destination_address,
--   destination_lat,
--   destination_lng,
--   scheduled_pickup_at
-- FROM bookings
-- WHERE deleted_at IS NULL
--   AND status NOT IN ('COMPLETED', 'CANCELLED', 'NO_SHOW')
--   AND (
--     (
--       origin_address IN (
--         'Bangkok, Thailand',
--         'Chiang Mai, Thailand',
--         'Phuket, Thailand',
--         'BKK',
--         'DMK',
--         'CNX',
--         'HKT'
--       )
--       AND origin_lat IS NULL
--     )
--     OR
--     (
--       destination_address IN (
--         'Bangkok, Thailand',
--         'Chiang Mai, Thailand',
--         'Phuket, Thailand',
--         'BKK',
--         'DMK',
--         'CNX',
--         'HKT'
--       )
--       AND destination_lat IS NULL
--     )
--   );
--
-- Rollback for locations (example; use values from the backup SELECT):
-- UPDATE locations
-- SET latitude = <previous_latitude>, longitude = <previous_longitude>,
--     display_name = <previous_display_name>
-- WHERE code = '<IATA>' AND type = 'AIRPORT' AND deleted_at IS NULL;
