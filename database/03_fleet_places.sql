-- TTaxi Platform — Fleet, pricing rules, places (MySQL 8)
-- Depends on: 00_database.sql, 01_identity.sql, 02_service_catalog.sql

USE ttaxi;

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- vehicle_types
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS vehicle_types (
  id SMALLINT UNSIGNED NOT NULL AUTO_INCREMENT,
  code ENUM('SEDAN', 'SUV', 'VIP_SUV', 'VAN', 'VIP_VAN', 'LUXURY') NOT NULL,
  name VARCHAR(50) NOT NULL,
  max_passengers TINYINT UNSIGNED NOT NULL,
  max_luggage TINYINT UNSIGNED NOT NULL,
  description VARCHAR(255) NULL DEFAULT NULL,
  sort_order SMALLINT NOT NULL DEFAULT 0,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at DATETIME NULL DEFAULT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_vehicle_types_code (code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- vehicle_prices (fallback base prices)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS vehicle_prices (
  id INT UNSIGNED NOT NULL AUTO_INCREMENT,
  service_type_id SMALLINT UNSIGNED NOT NULL,
  vehicle_type_id SMALLINT UNSIGNED NOT NULL,
  base_price DECIMAL(12, 2) NOT NULL,
  currency CHAR(3) NOT NULL DEFAULT 'THB',
  region_code VARCHAR(30) NULL DEFAULT NULL,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at DATETIME NULL DEFAULT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_vehicle_prices_service_vehicle_region (
    service_type_id, vehicle_type_id, region_code
  ),
  CONSTRAINT fk_vehicle_prices_service_type_id
    FOREIGN KEY (service_type_id) REFERENCES service_types (id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_vehicle_prices_vehicle_type_id
    FOREIGN KEY (vehicle_type_id) REFERENCES vehicle_types (id)
    ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- vehicle_price_rules
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS vehicle_price_rules (
  id INT UNSIGNED NOT NULL AUTO_INCREMENT,
  service_type_id SMALLINT UNSIGNED NOT NULL,
  vehicle_type_id SMALLINT UNSIGNED NOT NULL,
  name VARCHAR(100) NOT NULL,
  base_price DECIMAL(12, 2) NOT NULL,
  price_modifier_type ENUM('FIXED', 'PERCENT_ADD', 'PERCENT_OFF') NOT NULL DEFAULT 'FIXED',
  price_modifier_value DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
  currency CHAR(3) NOT NULL DEFAULT 'THB',
  priority INT NOT NULL DEFAULT 0,
  valid_from DATETIME NULL DEFAULT NULL,
  valid_to DATETIME NULL DEFAULT NULL,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  created_by BIGINT UNSIGNED NULL DEFAULT NULL,
  updated_by BIGINT UNSIGNED NULL DEFAULT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at DATETIME NULL DEFAULT NULL,
  PRIMARY KEY (id),
  KEY idx_vehicle_price_rules_match (
    service_type_id, vehicle_type_id, priority
  ),
  CONSTRAINT fk_vehicle_price_rules_service_type_id
    FOREIGN KEY (service_type_id) REFERENCES service_types (id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_vehicle_price_rules_vehicle_type_id
    FOREIGN KEY (vehicle_type_id) REFERENCES vehicle_types (id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_vehicle_price_rules_created_by
    FOREIGN KEY (created_by) REFERENCES users (id)
    ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT fk_vehicle_price_rules_updated_by
    FOREIGN KEY (updated_by) REFERENCES users (id)
    ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- vehicle_price_rule_conditions
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS vehicle_price_rule_conditions (
  id INT UNSIGNED NOT NULL AUTO_INCREMENT,
  rule_id INT UNSIGNED NOT NULL,
  condition_type ENUM(
    'DAY_OF_WEEK', 'TIME_RANGE', 'IS_HOLIDAY', 'SEASON',
    'ORIGIN_AIRPORT', 'DEST_REGION', 'SERVICE_TYPE'
  ) NOT NULL,
  condition_value VARCHAR(100) NOT NULL,
  operator ENUM('EQ', 'IN', 'BETWEEN', 'GTE', 'LTE') NOT NULL DEFAULT 'EQ',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at DATETIME NULL DEFAULT NULL,
  PRIMARY KEY (id),
  KEY idx_vehicle_price_rule_conditions_rule (rule_id, condition_type),
  CONSTRAINT fk_vehicle_price_rule_conditions_rule_id
    FOREIGN KEY (rule_id) REFERENCES vehicle_price_rules (id)
    ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- vehicle_capacity_rules (admin-editable vehicle recommendation)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS vehicle_capacity_rules (
  id INT UNSIGNED NOT NULL AUTO_INCREMENT,
  vehicle_type_id SMALLINT UNSIGNED NOT NULL,
  max_passengers TINYINT UNSIGNED NOT NULL,
  max_carriers_20_inch TINYINT UNSIGNED NOT NULL DEFAULT 0,
  max_carriers_24_inch_plus TINYINT UNSIGNED NOT NULL DEFAULT 0,
  max_golf_bags TINYINT UNSIGNED NOT NULL DEFAULT 0,
  max_special_luggage TINYINT UNSIGNED NOT NULL DEFAULT 0,
  priority INT NOT NULL DEFAULT 0,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  created_by BIGINT UNSIGNED NULL DEFAULT NULL,
  updated_by BIGINT UNSIGNED NULL DEFAULT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at DATETIME NULL DEFAULT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_vehicle_capacity_rules_vehicle_type (vehicle_type_id),
  CONSTRAINT fk_vehicle_capacity_rules_vehicle_type_id
    FOREIGN KEY (vehicle_type_id) REFERENCES vehicle_types (id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_vehicle_capacity_rules_created_by
    FOREIGN KEY (created_by) REFERENCES users (id)
    ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT fk_vehicle_capacity_rules_updated_by
    FOREIGN KEY (updated_by) REFERENCES users (id)
    ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- charge_policies (surcharge rules)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS charge_policies (
  id INT UNSIGNED NOT NULL AUTO_INCREMENT,
  charge_type ENUM(
    'VEHICLE_BASE', 'NAME_SIGN', 'NIGHT_SURCHARGE', 'AIRPORT_SURCHARGE',
    'TOLL_GATE', 'PROMOTION', 'COUPON', 'DRIVER_EXTRA',
    'SEASON_SURCHARGE', 'HOLIDAY_SURCHARGE', 'WAITING_CHARGE', 'OTHER'
  ) NOT NULL,
  name VARCHAR(100) NOT NULL,
  modifier_type ENUM(
    'FIXED', 'PERCENT_OF_BASE', 'PERCENT_OF_SUBTOTAL'
  ) NOT NULL DEFAULT 'FIXED',
  modifier_value DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
  currency CHAR(3) NOT NULL DEFAULT 'THB',
  priority INT NOT NULL DEFAULT 0,
  valid_from DATETIME NULL DEFAULT NULL,
  valid_to DATETIME NULL DEFAULT NULL,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  created_by BIGINT UNSIGNED NULL DEFAULT NULL,
  updated_by BIGINT UNSIGNED NULL DEFAULT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at DATETIME NULL DEFAULT NULL,
  PRIMARY KEY (id),
  KEY idx_charge_policies_type_priority (charge_type, priority),
  CONSTRAINT fk_charge_policies_created_by
    FOREIGN KEY (created_by) REFERENCES users (id)
    ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT fk_charge_policies_updated_by
    FOREIGN KEY (updated_by) REFERENCES users (id)
    ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- charge_policy_conditions
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS charge_policy_conditions (
  id INT UNSIGNED NOT NULL AUTO_INCREMENT,
  policy_id INT UNSIGNED NOT NULL,
  condition_type ENUM(
    'DAY_OF_WEEK', 'TIME_RANGE', 'IS_HOLIDAY', 'SEASON',
    'ORIGIN_AIRPORT', 'DEST_REGION', 'SERVICE_TYPE'
  ) NOT NULL,
  condition_value VARCHAR(100) NOT NULL,
  operator ENUM('EQ', 'IN', 'BETWEEN', 'GTE', 'LTE') NOT NULL DEFAULT 'EQ',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at DATETIME NULL DEFAULT NULL,
  PRIMARY KEY (id),
  KEY idx_charge_policy_conditions_policy (policy_id, condition_type),
  CONSTRAINT fk_charge_policy_conditions_policy_id
    FOREIGN KEY (policy_id) REFERENCES charge_policies (id)
    ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- airports
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS airports (
  id SMALLINT UNSIGNED NOT NULL AUTO_INCREMENT,
  iata_code CHAR(3) NOT NULL,
  icao_code CHAR(4) NULL DEFAULT NULL,
  country_code CHAR(2) NOT NULL DEFAULT 'TH',
  city VARCHAR(100) NULL DEFAULT NULL,
  name VARCHAR(200) NOT NULL,
  timezone VARCHAR(50) NULL DEFAULT NULL,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  created_by BIGINT UNSIGNED NULL DEFAULT NULL,
  updated_by BIGINT UNSIGNED NULL DEFAULT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at DATETIME NULL DEFAULT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_airports_iata (iata_code),
  CONSTRAINT fk_airports_created_by
    FOREIGN KEY (created_by) REFERENCES users (id)
    ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT fk_airports_updated_by
    FOREIGN KEY (updated_by) REFERENCES users (id)
    ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- golf_courses
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS golf_courses (
  id INT UNSIGNED NOT NULL AUTO_INCREMENT,
  region VARCHAR(50) NOT NULL,
  name VARCHAR(200) NOT NULL,
  address VARCHAR(500) NULL DEFAULT NULL,
  place_id VARCHAR(255) NULL DEFAULT NULL,
  lat DECIMAL(10, 7) NULL DEFAULT NULL,
  lng DECIMAL(10, 7) NULL DEFAULT NULL,
  phone VARCHAR(30) NULL DEFAULT NULL,
  website VARCHAR(512) NULL DEFAULT NULL,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  created_by BIGINT UNSIGNED NULL DEFAULT NULL,
  updated_by BIGINT UNSIGNED NULL DEFAULT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at DATETIME NULL DEFAULT NULL,
  PRIMARY KEY (id),
  KEY idx_golf_courses_region_active (region, is_active),
  CONSTRAINT fk_golf_courses_created_by
    FOREIGN KEY (created_by) REFERENCES users (id)
    ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT fk_golf_courses_updated_by
    FOREIGN KEY (updated_by) REFERENCES users (id)
    ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- drivers
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS drivers (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id BIGINT UNSIGNED NULL DEFAULT NULL,
  name VARCHAR(100) NOT NULL,
  phone VARCHAR(30) NOT NULL,
  license_number VARCHAR(50) NULL DEFAULT NULL,
  status ENUM('AVAILABLE', 'ON_TRIP', 'OFFLINE', 'SUSPENDED') NOT NULL DEFAULT 'OFFLINE',
  primary_vehicle_type_id SMALLINT UNSIGNED NULL DEFAULT NULL,
  rating_avg DECIMAL(3, 2) NULL DEFAULT NULL,
  rating_count INT UNSIGNED NOT NULL DEFAULT 0,
  current_lat DECIMAL(10, 7) NULL DEFAULT NULL,
  current_lng DECIMAL(10, 7) NULL DEFAULT NULL,
  location_updated_at DATETIME NULL DEFAULT NULL,
  is_online TINYINT(1) NOT NULL DEFAULT 0,
  last_seen_at DATETIME NULL DEFAULT NULL,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  created_by BIGINT UNSIGNED NULL DEFAULT NULL,
  updated_by BIGINT UNSIGNED NULL DEFAULT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at DATETIME NULL DEFAULT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_drivers_user_id (user_id),
  KEY idx_drivers_status_active (status, is_active),
  KEY idx_drivers_online_status (is_online, status),
  KEY idx_drivers_last_seen (last_seen_at),
  CONSTRAINT fk_drivers_user_id
    FOREIGN KEY (user_id) REFERENCES users (id)
    ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT fk_drivers_primary_vehicle_type_id
    FOREIGN KEY (primary_vehicle_type_id) REFERENCES vehicle_types (id)
    ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT fk_drivers_created_by
    FOREIGN KEY (created_by) REFERENCES users (id)
    ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT fk_drivers_updated_by
    FOREIGN KEY (updated_by) REFERENCES users (id)
    ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- driver_vehicles
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS driver_vehicles (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  driver_id BIGINT UNSIGNED NOT NULL,
  vehicle_type_id SMALLINT UNSIGNED NOT NULL,
  plate_number VARCHAR(20) NOT NULL,
  model_name VARCHAR(100) NULL DEFAULT NULL,
  color VARCHAR(30) NULL DEFAULT NULL,
  is_primary TINYINT(1) NOT NULL DEFAULT 0,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  created_by BIGINT UNSIGNED NULL DEFAULT NULL,
  updated_by BIGINT UNSIGNED NULL DEFAULT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at DATETIME NULL DEFAULT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_driver_vehicles_plate (plate_number),
  KEY idx_driver_vehicles_driver (driver_id),
  CONSTRAINT fk_driver_vehicles_driver_id
    FOREIGN KEY (driver_id) REFERENCES drivers (id)
    ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT fk_driver_vehicles_vehicle_type_id
    FOREIGN KEY (vehicle_type_id) REFERENCES vehicle_types (id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_driver_vehicles_created_by
    FOREIGN KEY (created_by) REFERENCES users (id)
    ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT fk_driver_vehicles_updated_by
    FOREIGN KEY (updated_by) REFERENCES users (id)
    ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- driver_assignment_weights
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS driver_assignment_weights (
  id INT UNSIGNED NOT NULL AUTO_INCREMENT,
  factor_code ENUM(
    'DISTANCE', 'ONLINE', 'VEHICLE_MATCH', 'RATING', 'FAIRNESS', 'REGION'
  ) NOT NULL,
  weight DECIMAL(5, 2) NOT NULL DEFAULT 1.00,
  description VARCHAR(255) NULL DEFAULT NULL,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  created_by BIGINT UNSIGNED NULL DEFAULT NULL,
  updated_by BIGINT UNSIGNED NULL DEFAULT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at DATETIME NULL DEFAULT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_driver_assignment_weights_factor (factor_code),
  CONSTRAINT fk_driver_assignment_weights_created_by
    FOREIGN KEY (created_by) REFERENCES users (id)
    ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT fk_driver_assignment_weights_updated_by
    FOREIGN KEY (updated_by) REFERENCES users (id)
    ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
