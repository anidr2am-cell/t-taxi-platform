-- T-Ride urgent request booking negotiation (phase 1 schema).
-- Adds urgent flags on bookings and negotiation/attempt tracking tables.
-- Safe to re-run when columns, tables, or constraints already exist.

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS booking_urgent_negotiations (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  booking_id BIGINT UNSIGNED NOT NULL,
  status ENUM(
    'BROADCASTING',
    'LOCKED',
    'AWAITING_CUSTOMER',
    'CONFIRMED',
    'CANCELLED'
  ) NOT NULL,
  attempt_count TINYINT UNSIGNED NOT NULL DEFAULT 0,
  locked_driver_id BIGINT UNSIGNED NULL DEFAULT NULL,
  locked_at DATETIME(3) NULL DEFAULT NULL,
  lock_expires_at DATETIME(3) NULL DEFAULT NULL,
  customer_decision_expires_at DATETIME(3) NULL DEFAULT NULL,
  min_required_eta_minutes INT UNSIGNED NULL DEFAULT NULL,
  closed_at DATETIME(3) NULL DEFAULT NULL,
  closed_reason VARCHAR(64) NULL DEFAULT NULL,
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uq_active_booking (booking_id, status),
  CONSTRAINT fk_booking_urgent_negotiations_booking_id
    FOREIGN KEY (booking_id) REFERENCES bookings (id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_booking_urgent_negotiations_locked_driver_id
    FOREIGN KEY (locked_driver_id) REFERENCES drivers (id)
    ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS booking_urgent_negotiation_attempts (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  negotiation_id BIGINT UNSIGNED NOT NULL,
  attempt_number TINYINT UNSIGNED NOT NULL,
  driver_id BIGINT UNSIGNED NOT NULL,
  proposed_eta_minutes INT UNSIGNED NULL DEFAULT NULL,
  eta_submitted_at DATETIME(3) NULL DEFAULT NULL,
  outcome ENUM(
    'IN_PROGRESS',
    'DRIVER_ETA_TIMEOUT',
    'CUSTOMER_ACCEPTED',
    'CUSTOMER_REJECTED',
    'CUSTOMER_AUTO_REJECTED'
  ) NOT NULL DEFAULT 'IN_PROGRESS',
  outcome_at DATETIME(3) NULL DEFAULT NULL,
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uq_negotiation_attempt (negotiation_id, attempt_number),
  CONSTRAINT fk_booking_urgent_negotiation_attempts_negotiation_id
    FOREIGN KEY (negotiation_id) REFERENCES booking_urgent_negotiations (id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_booking_urgent_negotiation_attempts_driver_id
    FOREIGN KEY (driver_id) REFERENCES drivers (id)
    ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

SET @is_urgent_request_exists = (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'bookings'
    AND COLUMN_NAME = 'is_urgent_request'
);

SET @sql = IF(
  @is_urgent_request_exists = 0,
  'ALTER TABLE bookings ADD COLUMN is_urgent_request TINYINT(1) NOT NULL DEFAULT 0',
  'SELECT 1'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @urgent_negotiation_id_exists = (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'bookings'
    AND COLUMN_NAME = 'urgent_negotiation_id'
);

SET @sql = IF(
  @urgent_negotiation_id_exists = 0,
  'ALTER TABLE bookings ADD COLUMN urgent_negotiation_id BIGINT UNSIGNED NULL DEFAULT NULL',
  'SELECT 1'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @bookings_urgent_negotiation_fk_exists = (
  SELECT COUNT(*)
  FROM information_schema.TABLE_CONSTRAINTS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'bookings'
    AND CONSTRAINT_NAME = 'fk_bookings_urgent_negotiation_id'
    AND CONSTRAINT_TYPE = 'FOREIGN KEY'
);

SET @sql = IF(
  @bookings_urgent_negotiation_fk_exists = 0,
  'ALTER TABLE bookings ADD CONSTRAINT fk_bookings_urgent_negotiation_id FOREIGN KEY (urgent_negotiation_id) REFERENCES booking_urgent_negotiations (id) ON DELETE SET NULL ON UPDATE CASCADE',
  'SELECT 1'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;
