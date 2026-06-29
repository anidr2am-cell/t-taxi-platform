-- TTaxi Platform — Flight monitor fields (Pack 21)
-- Depends on: 04_booking_core.sql
-- Rerunnable: adds columns/indexes only when missing.

USE ttaxi;

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

SET @col_exists = (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'booking_transfer_details'
    AND COLUMN_NAME = 'airline_code'
);
SET @sql = IF(
  @col_exists = 0,
  'ALTER TABLE booking_transfer_details ADD COLUMN airline_code VARCHAR(10) NULL DEFAULT NULL AFTER flight_number',
  'SELECT 1'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @col_exists = (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'booking_transfer_details'
    AND COLUMN_NAME = 'flight_date'
);
SET @sql = IF(
  @col_exists = 0,
  'ALTER TABLE booking_transfer_details ADD COLUMN flight_date DATE NULL DEFAULT NULL AFTER airline_code',
  'SELECT 1'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @col_exists = (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'booking_transfer_details'
    AND COLUMN_NAME = 'departure_airport_iata'
);
SET @sql = IF(
  @col_exists = 0,
  'ALTER TABLE booking_transfer_details ADD COLUMN departure_airport_iata CHAR(3) NULL DEFAULT NULL AFTER flight_date',
  'SELECT 1'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @col_exists = (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'booking_transfer_details'
    AND COLUMN_NAME = 'arrival_airport_iata'
);
SET @sql = IF(
  @col_exists = 0,
  'ALTER TABLE booking_transfer_details ADD COLUMN arrival_airport_iata CHAR(3) NULL DEFAULT NULL AFTER departure_airport_iata',
  'SELECT 1'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @col_exists = (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'booking_transfer_details'
    AND COLUMN_NAME = 'flight_actual_arrival_at'
);
SET @sql = IF(
  @col_exists = 0,
  'ALTER TABLE booking_transfer_details ADD COLUMN flight_actual_arrival_at DATETIME NULL DEFAULT NULL AFTER flight_estimated_arrival_at',
  'SELECT 1'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @col_exists = (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'booking_transfer_details'
    AND COLUMN_NAME = 'flight_status'
);
SET @sql = IF(
  @col_exists = 0,
  'ALTER TABLE booking_transfer_details ADD COLUMN flight_status ENUM(''SCHEDULED'',''ACTIVE'',''DELAYED'',''LANDED'',''CANCELLED'',''DIVERTED'',''UNKNOWN'') NULL DEFAULT NULL AFTER delay_status',
  'SELECT 1'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @col_exists = (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'booking_transfer_details'
    AND COLUMN_NAME = 'last_synced_at'
);
SET @sql = IF(
  @col_exists = 0,
  'ALTER TABLE booking_transfer_details ADD COLUMN last_synced_at DATETIME NULL DEFAULT NULL AFTER flight_raw_data',
  'SELECT 1'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @col_exists = (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'booking_transfer_details'
    AND COLUMN_NAME = 'sync_status'
);
SET @sql = IF(
  @col_exists = 0,
  'ALTER TABLE booking_transfer_details ADD COLUMN sync_status ENUM(''NEVER'',''SUCCESS'',''FAILED'',''SKIPPED'',''NOT_CONFIGURED'',''RATE_LIMITED'') NOT NULL DEFAULT ''NEVER'' AFTER last_synced_at',
  'SELECT 1'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @col_exists = (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'booking_transfer_details'
    AND COLUMN_NAME = 'sync_error'
);
SET @sql = IF(
  @col_exists = 0,
  'ALTER TABLE booking_transfer_details ADD COLUMN sync_error VARCHAR(500) NULL DEFAULT NULL AFTER sync_status',
  'SELECT 1'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @idx_exists = (
  SELECT COUNT(*) FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'booking_transfer_details'
    AND INDEX_NAME = 'idx_btd_flight_status'
);
SET @sql = IF(
  @idx_exists = 0,
  'CREATE INDEX idx_btd_flight_status ON booking_transfer_details (flight_status, last_synced_at)',
  'SELECT 1'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @idx_exists = (
  SELECT COUNT(*) FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'booking_transfer_details'
    AND INDEX_NAME = 'idx_btd_flight_date'
);
SET @sql = IF(
  @idx_exists = 0,
  'CREATE INDEX idx_btd_flight_date ON booking_transfer_details (flight_date, flight_number)',
  'SELECT 1'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;
