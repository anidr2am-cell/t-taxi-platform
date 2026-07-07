-- TTaxi Platform — Booking core (MySQL 8 / MariaDB 10.11)
-- Depends on: 00_database.sql through 03_fleet_places.sql

USE ttaxi;

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- bookings
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS bookings (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  booking_number VARCHAR(20) NOT NULL,
  status ENUM(
    'PENDING', 'CONFIRMED', 'DRIVER_ASSIGNED', 'DRIVER_ARRIVED',
    'PICKED_UP', 'COMPLETED', 'CANCELLED', 'NO_SHOW'
  ) NOT NULL DEFAULT 'PENDING',
  service_type_id SMALLINT UNSIGNED NOT NULL,
  origin_address VARCHAR(500) NULL DEFAULT NULL,
  origin_place_id VARCHAR(255) NULL DEFAULT NULL,
  origin_lat DECIMAL(10, 7) NULL DEFAULT NULL,
  origin_lng DECIMAL(10, 7) NULL DEFAULT NULL,
  destination_address VARCHAR(500) NULL DEFAULT NULL,
  destination_place_id VARCHAR(255) NULL DEFAULT NULL,
  destination_lat DECIMAL(10, 7) NULL DEFAULT NULL,
  destination_lng DECIMAL(10, 7) NULL DEFAULT NULL,
  scheduled_pickup_at DATETIME NULL DEFAULT NULL,
  vehicle_type_id SMALLINT UNSIGNED NOT NULL,
  recommended_vehicle_type_id SMALLINT UNSIGNED NULL DEFAULT NULL,
  vehicle_count TINYINT UNSIGNED NOT NULL DEFAULT 1,
  pricing_rule_id INT UNSIGNED NULL DEFAULT NULL,
  total_amount DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
  currency CHAR(3) NOT NULL DEFAULT 'THB',
  payment_status ENUM('UNPAID', 'PENDING', 'PAID', 'REFUNDED', 'FAILED') NOT NULL DEFAULT 'UNPAID',
  customer_user_id BIGINT UNSIGNED NULL DEFAULT NULL,
  customer_name VARCHAR(100) NOT NULL,
  customer_email VARCHAR(255) NOT NULL,
  customer_phone VARCHAR(30) NOT NULL,
  customer_country_code CHAR(2) NULL DEFAULT NULL,
  driver_id BIGINT UNSIGNED NULL DEFAULT NULL,
  special_requests TEXT NULL,
  cancelled_at DATETIME NULL DEFAULT NULL,
  cancellation_reason VARCHAR(500) NULL DEFAULT NULL,
  completed_at DATETIME NULL DEFAULT NULL,
  metadata JSON NULL,
  created_by BIGINT UNSIGNED NULL DEFAULT NULL,
  updated_by BIGINT UNSIGNED NULL DEFAULT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at DATETIME NULL DEFAULT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_bookings_number (booking_number),
  KEY idx_bookings_status_scheduled (status, scheduled_pickup_at),
  KEY idx_bookings_customer (customer_user_id),
  KEY idx_bookings_driver (driver_id),
  KEY idx_bookings_service_type (service_type_id),
  KEY idx_bookings_created (created_at),
  KEY idx_bookings_payment_status (payment_status),
  CONSTRAINT fk_bookings_service_type_id
    FOREIGN KEY (service_type_id) REFERENCES service_types (id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_bookings_vehicle_type_id
    FOREIGN KEY (vehicle_type_id) REFERENCES vehicle_types (id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_bookings_recommended_vehicle_type_id
    FOREIGN KEY (recommended_vehicle_type_id) REFERENCES vehicle_types (id)
    ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT fk_bookings_pricing_rule_id
    FOREIGN KEY (pricing_rule_id) REFERENCES vehicle_price_rules (id)
    ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT fk_bookings_customer_user_id
    FOREIGN KEY (customer_user_id) REFERENCES users (id)
    ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT fk_bookings_driver_id
    FOREIGN KEY (driver_id) REFERENCES drivers (id)
    ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT fk_bookings_created_by
    FOREIGN KEY (created_by) REFERENCES users (id)
    ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT fk_bookings_updated_by
    FOREIGN KEY (updated_by) REFERENCES users (id)
    ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- booking_passengers
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS booking_passengers (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  booking_id BIGINT UNSIGNED NOT NULL,
  adults TINYINT UNSIGNED NOT NULL DEFAULT 1,
  children TINYINT UNSIGNED NOT NULL DEFAULT 0,
  infants TINYINT UNSIGNED NOT NULL DEFAULT 0,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at DATETIME NULL DEFAULT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_booking_passengers_booking (booking_id),
  CONSTRAINT fk_booking_passengers_booking_id
    FOREIGN KEY (booking_id) REFERENCES bookings (id)
    ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- booking_luggage
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS booking_luggage (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  booking_id BIGINT UNSIGNED NOT NULL,
  carriers_20_inch TINYINT UNSIGNED NOT NULL DEFAULT 0,
  carriers_24_inch_plus TINYINT UNSIGNED NOT NULL DEFAULT 0,
  golf_bags TINYINT UNSIGNED NOT NULL DEFAULT 0,
  special_items TEXT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at DATETIME NULL DEFAULT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_booking_luggage_booking (booking_id),
  CONSTRAINT fk_booking_luggage_booking_id
    FOREIGN KEY (booking_id) REFERENCES bookings (id)
    ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- booking_transfer_details
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS booking_transfer_details (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  booking_id BIGINT UNSIGNED NOT NULL,
  airport_id SMALLINT UNSIGNED NULL DEFAULT NULL,
  airport_code_custom VARCHAR(10) NULL DEFAULT NULL,
  flight_number VARCHAR(20) NULL DEFAULT NULL,
  flight_scheduled_arrival_at DATETIME NULL DEFAULT NULL,
  flight_estimated_arrival_at DATETIME NULL DEFAULT NULL,
  delay_minutes SMALLINT NULL DEFAULT NULL,
  delay_status VARCHAR(50) NULL DEFAULT NULL,
  flight_raw_data JSON NULL,
  golf_course_id INT UNSIGNED NULL DEFAULT NULL,
  golf_region VARCHAR(50) NULL DEFAULT NULL,
  driver_included TINYINT(1) NOT NULL DEFAULT 0,
  pickup_time_local TIME NULL DEFAULT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at DATETIME NULL DEFAULT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_booking_transfer_details_booking (booking_id),
  KEY idx_booking_transfer_flight (
    flight_number, flight_scheduled_arrival_at
  ),
  CONSTRAINT fk_booking_transfer_details_booking_id
    FOREIGN KEY (booking_id) REFERENCES bookings (id)
    ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT fk_booking_transfer_details_airport_id
    FOREIGN KEY (airport_id) REFERENCES airports (id)
    ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT fk_booking_transfer_details_golf_course_id
    FOREIGN KEY (golf_course_id) REFERENCES golf_courses (id)
    ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- booking_charge_items
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS booking_charge_items (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  booking_id BIGINT UNSIGNED NOT NULL,
  charge_type ENUM(
    'VEHICLE_BASE', 'NAME_SIGN', 'NIGHT_SURCHARGE', 'AIRPORT_SURCHARGE',
    'TOLL_GATE', 'PROMOTION', 'COUPON', 'DRIVER_EXTRA',
    'SEASON_SURCHARGE', 'HOLIDAY_SURCHARGE', 'WAITING_CHARGE', 'OTHER'
  ) NOT NULL,
  description VARCHAR(255) NULL DEFAULT NULL,
  quantity DECIMAL(10, 2) NOT NULL DEFAULT 1.00,
  unit_price DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
  amount DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
  reference_type VARCHAR(30) NULL DEFAULT NULL,
  reference_id BIGINT UNSIGNED NULL DEFAULT NULL,
  metadata JSON NULL,
  created_by BIGINT UNSIGNED NULL DEFAULT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at DATETIME NULL DEFAULT NULL,
  PRIMARY KEY (id),
  KEY idx_booking_charge_items_booking (booking_id),
  KEY idx_booking_charge_items_type (charge_type),
  CONSTRAINT fk_booking_charge_items_booking_id
    FOREIGN KEY (booking_id) REFERENCES bookings (id)
    ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT fk_booking_charge_items_created_by
    FOREIGN KEY (created_by) REFERENCES users (id)
    ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- booking_status_logs
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS booking_status_logs (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  booking_id BIGINT UNSIGNED NOT NULL,
  from_status ENUM(
    'PENDING', 'CONFIRMED', 'DRIVER_ASSIGNED', 'DRIVER_ARRIVED',
    'PICKED_UP', 'COMPLETED', 'CANCELLED', 'NO_SHOW'
  ) NULL DEFAULT NULL,
  to_status ENUM(
    'PENDING', 'CONFIRMED', 'DRIVER_ASSIGNED', 'DRIVER_ARRIVED',
    'PICKED_UP', 'COMPLETED', 'CANCELLED', 'NO_SHOW'
  ) NOT NULL,
  changed_by_user_id BIGINT UNSIGNED NULL DEFAULT NULL,
  changed_by_role ENUM('CUSTOMER', 'DRIVER', 'ADMIN', 'SYSTEM', 'SUPER_ADMIN') NULL DEFAULT NULL,
  reason VARCHAR(100) NULL DEFAULT NULL,
  memo VARCHAR(500) NULL DEFAULT NULL,
  note VARCHAR(500) NULL DEFAULT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_booking_status_logs_booking (booking_id, created_at),
  CONSTRAINT fk_booking_status_logs_booking_id
    FOREIGN KEY (booking_id) REFERENCES bookings (id)
    ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT fk_booking_status_logs_changed_by_user_id
    FOREIGN KEY (changed_by_user_id) REFERENCES users (id)
    ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- booking_driver_assignments
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS booking_driver_assignments (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  booking_id BIGINT UNSIGNED NOT NULL,
  driver_id BIGINT UNSIGNED NOT NULL,
  driver_vehicle_id BIGINT UNSIGNED NULL DEFAULT NULL,
  status ENUM('ASSIGNED', 'ACCEPTED', 'REJECTED', 'COMPLETED', 'CANCELLED') NOT NULL DEFAULT 'ASSIGNED',
  assigned_by_user_id BIGINT UNSIGNED NULL DEFAULT NULL,
  assignment_reason VARCHAR(255) NULL DEFAULT NULL,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  assigned_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  unassigned_at DATETIME NULL DEFAULT NULL,
  accepted_at DATETIME NULL DEFAULT NULL,
  completed_at DATETIME NULL DEFAULT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at DATETIME NULL DEFAULT NULL,
  active_booking_id BIGINT UNSIGNED GENERATED ALWAYS AS (
    CASE WHEN is_active = 1 AND deleted_at IS NULL THEN booking_id ELSE NULL END
  ) STORED,
  PRIMARY KEY (id),
  UNIQUE KEY uk_bda_one_active_per_booking (active_booking_id),
  KEY idx_booking_driver_assignments_booking_active (booking_id, is_active),
  KEY idx_booking_driver_assignments_driver_active (driver_id, is_active),
  KEY idx_booking_driver_assignments_driver_status (driver_id, status),
  CONSTRAINT fk_booking_driver_assignments_booking_id
    FOREIGN KEY (booking_id) REFERENCES bookings (id)
    ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT fk_booking_driver_assignments_driver_id
    FOREIGN KEY (driver_id) REFERENCES drivers (id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_booking_driver_assignments_driver_vehicle_id
    FOREIGN KEY (driver_vehicle_id) REFERENCES driver_vehicles (id)
    ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT fk_booking_driver_assignments_assigned_by_user_id
    FOREIGN KEY (assigned_by_user_id) REFERENCES users (id)
    ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT chk_bda_active_state CHECK (
    is_active <> 1
    OR deleted_at IS NOT NULL
    OR (
      unassigned_at IS NULL
      AND status IN ('ASSIGNED', 'ACCEPTED')
    )
  )
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- booking_admin_notes
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS booking_admin_notes (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  booking_id BIGINT UNSIGNED NOT NULL,
  admin_user_id BIGINT UNSIGNED NOT NULL,
  note TEXT NOT NULL,
  is_private TINYINT(1) NOT NULL DEFAULT 1,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  deleted_at DATETIME NULL DEFAULT NULL,
  PRIMARY KEY (id),
  KEY idx_booking_admin_notes_booking (booking_id, created_at),
  CONSTRAINT fk_booking_admin_notes_booking_id
    FOREIGN KEY (booking_id) REFERENCES bookings (id)
    ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT fk_booking_admin_notes_admin_user_id
    FOREIGN KEY (admin_user_id) REFERENCES users (id)
    ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- booking_activity_logs
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS booking_activity_logs (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  booking_id BIGINT UNSIGNED NOT NULL,
  activity_type VARCHAR(50) NOT NULL,
  actor_user_id BIGINT UNSIGNED NULL DEFAULT NULL,
  actor_role ENUM('CUSTOMER', 'DRIVER', 'ADMIN', 'SYSTEM', 'SUPER_ADMIN') NULL DEFAULT NULL,
  description VARCHAR(500) NULL DEFAULT NULL,
  payload JSON NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_booking_activity_logs_booking (booking_id, created_at),
  KEY idx_booking_activity_logs_type (activity_type),
  CONSTRAINT fk_booking_activity_logs_booking_id
    FOREIGN KEY (booking_id) REFERENCES bookings (id)
    ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT fk_booking_activity_logs_actor_user_id
    FOREIGN KEY (actor_user_id) REFERENCES users (id)
    ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- booking_number_sequences
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS booking_number_sequences (
  id INT UNSIGNED NOT NULL AUTO_INCREMENT,
  date_prefix CHAR(8) NOT NULL,
  last_sequence INT UNSIGNED NOT NULL DEFAULT 0,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_booking_number_sequences_date (date_prefix)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- guest_access_tokens
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS guest_access_tokens (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  booking_id BIGINT UNSIGNED NOT NULL,
  token_hash CHAR(64) NOT NULL,
  expires_at DATETIME NOT NULL,
  revoked_at DATETIME NULL DEFAULT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_guest_access_tokens_hash (token_hash),
  KEY idx_guest_access_tokens_booking (booking_id),
  KEY idx_guest_access_tokens_expires (expires_at),
  CONSTRAINT fk_guest_access_tokens_booking_id
    FOREIGN KEY (booking_id) REFERENCES bookings (id)
    ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
