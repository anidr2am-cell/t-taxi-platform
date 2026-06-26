-- TTaxi Platform — Normalized pricing architecture (MySQL 8)
-- Depends on: prior migrations through 14_pricing_integrity.sql
--
-- Introduces: locations, routes, route-scoped vehicle_prices, simplified charge_policies.
-- Removes: vehicle_price_rules, vehicle_price_rule_conditions, charge_policy_conditions.

USE ttaxi;

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- locations — master location registry
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS locations (
  id INT UNSIGNED NOT NULL AUTO_INCREMENT,
  code VARCHAR(50) NOT NULL,
  type ENUM('AIRPORT', 'CITY', 'HOTEL', 'GOLF', 'PLACE') NOT NULL,
  display_name VARCHAR(200) NOT NULL,
  google_place_id VARCHAR(255) NULL DEFAULT NULL,
  airport_id SMALLINT UNSIGNED NULL DEFAULT NULL,
  golf_course_id INT UNSIGNED NULL DEFAULT NULL,
  latitude DECIMAL(10, 7) NULL DEFAULT NULL,
  longitude DECIMAL(10, 7) NULL DEFAULT NULL,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at DATETIME NULL DEFAULT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_locations_code (code),
  KEY idx_locations_type_active (type, is_active),
  CONSTRAINT fk_locations_airport_id
    FOREIGN KEY (airport_id) REFERENCES airports (id)
    ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT fk_locations_golf_course_id
    FOREIGN KEY (golf_course_id) REFERENCES golf_courses (id)
    ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- routes — travel routes (no embedded pricing)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS routes (
  id INT UNSIGNED NOT NULL AUTO_INCREMENT,
  service_type_id SMALLINT UNSIGNED NOT NULL,
  origin_location_id INT UNSIGNED NOT NULL,
  destination_location_id INT UNSIGNED NOT NULL,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  display_order INT NOT NULL DEFAULT 0,
  effective_from DATETIME NULL DEFAULT NULL,
  effective_to DATETIME NULL DEFAULT NULL,
  created_by BIGINT UNSIGNED NULL DEFAULT NULL,
  updated_by BIGINT UNSIGNED NULL DEFAULT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at DATETIME NULL DEFAULT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_routes_service_origin_dest (
    service_type_id, origin_location_id, destination_location_id
  ),
  KEY idx_routes_active_order (is_active, display_order),
  CONSTRAINT fk_routes_service_type_id
    FOREIGN KEY (service_type_id) REFERENCES service_types (id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_routes_origin_location_id
    FOREIGN KEY (origin_location_id) REFERENCES locations (id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_routes_destination_location_id
    FOREIGN KEY (destination_location_id) REFERENCES locations (id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_routes_created_by
    FOREIGN KEY (created_by) REFERENCES users (id)
    ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT fk_routes_updated_by
    FOREIGN KEY (updated_by) REFERENCES users (id)
    ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- Drop legacy pricing rule tables and rebuild vehicle_prices / charge_policies
-- ---------------------------------------------------------------------------
SET @fk_exists = (
  SELECT COUNT(*)
  FROM information_schema.TABLE_CONSTRAINTS
  WHERE CONSTRAINT_SCHEMA = DATABASE()
    AND TABLE_NAME = 'bookings'
    AND CONSTRAINT_NAME = 'fk_bookings_pricing_rule_id'
    AND CONSTRAINT_TYPE = 'FOREIGN KEY'
);

SET @drop_fk_sql = IF(
  @fk_exists > 0,
  'ALTER TABLE bookings DROP FOREIGN KEY fk_bookings_pricing_rule_id',
  'SELECT 1'
);
PREPARE stmt_drop_fk FROM @drop_fk_sql;
EXECUTE stmt_drop_fk;
DEALLOCATE PREPARE stmt_drop_fk;

SET @col_exists = (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'bookings'
    AND COLUMN_NAME = 'pricing_rule_id'
);

SET @drop_col_sql = IF(
  @col_exists > 0,
  'ALTER TABLE bookings DROP COLUMN pricing_rule_id',
  'SELECT 1'
);
PREPARE stmt_drop_col FROM @drop_col_sql;
EXECUTE stmt_drop_col;
DEALLOCATE PREPARE stmt_drop_col;

DROP TABLE IF EXISTS charge_policy_conditions;
DROP TABLE IF EXISTS vehicle_price_rule_conditions;
DROP TABLE IF EXISTS vehicle_price_rules;

DROP TRIGGER IF EXISTS trg_bci_before_insert_validate;
DROP TRIGGER IF EXISTS trg_bci_before_update_validate;

DROP TABLE IF EXISTS vehicle_prices;

CREATE TABLE vehicle_prices (
  id INT UNSIGNED NOT NULL AUTO_INCREMENT,
  route_id INT UNSIGNED NOT NULL,
  vehicle_type_id SMALLINT UNSIGNED NOT NULL,
  price DECIMAL(12, 2) NOT NULL,
  currency CHAR(3) NOT NULL DEFAULT 'THB',
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  effective_from DATETIME NULL DEFAULT NULL,
  effective_to DATETIME NULL DEFAULT NULL,
  created_by BIGINT UNSIGNED NULL DEFAULT NULL,
  updated_by BIGINT UNSIGNED NULL DEFAULT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at DATETIME NULL DEFAULT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_vehicle_prices_route_vehicle (route_id, vehicle_type_id),
  KEY idx_vehicle_prices_active (is_active),
  CONSTRAINT fk_vehicle_prices_route_id
    FOREIGN KEY (route_id) REFERENCES routes (id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_vehicle_prices_vehicle_type_id
    FOREIGN KEY (vehicle_type_id) REFERENCES vehicle_types (id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_vehicle_prices_created_by
    FOREIGN KEY (created_by) REFERENCES users (id)
    ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT fk_vehicle_prices_updated_by
    FOREIGN KEY (updated_by) REFERENCES users (id)
    ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS charge_policies;

CREATE TABLE charge_policies (
  id INT UNSIGNED NOT NULL AUTO_INCREMENT,
  charge_type ENUM(
    'NAME_SIGN', 'WAITING', 'PARKING', 'TOLL', 'HOLIDAY', 'NIGHT', 'AIRPORT'
  ) NOT NULL,
  calculation_type ENUM(
    'FIXED', 'PERCENT_OF_BASE', 'PERCENT_OF_SUBTOTAL'
  ) NOT NULL DEFAULT 'FIXED',
  amount DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  effective_from DATETIME NULL DEFAULT NULL,
  effective_to DATETIME NULL DEFAULT NULL,
  created_by BIGINT UNSIGNED NULL DEFAULT NULL,
  updated_by BIGINT UNSIGNED NULL DEFAULT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at DATETIME NULL DEFAULT NULL,
  PRIMARY KEY (id),
  KEY idx_charge_policies_type_active (charge_type, is_active),
  CONSTRAINT fk_charge_policies_created_by
    FOREIGN KEY (created_by) REFERENCES users (id)
    ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT fk_charge_policies_updated_by
    FOREIGN KEY (updated_by) REFERENCES users (id)
    ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

SET @route_col_exists = (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'bookings'
    AND COLUMN_NAME = 'route_id'
);

SET @add_route_col_sql = IF(
  @route_col_exists = 0,
  'ALTER TABLE bookings ADD COLUMN route_id INT UNSIGNED NULL DEFAULT NULL AFTER vehicle_count',
  'SELECT 1'
);
PREPARE stmt_add_route FROM @add_route_col_sql;
EXECUTE stmt_add_route;
DEALLOCATE PREPARE stmt_add_route;

SET @route_fk_exists = (
  SELECT COUNT(*)
  FROM information_schema.TABLE_CONSTRAINTS
  WHERE CONSTRAINT_SCHEMA = DATABASE()
    AND TABLE_NAME = 'bookings'
    AND CONSTRAINT_NAME = 'fk_bookings_route_id'
    AND CONSTRAINT_TYPE = 'FOREIGN KEY'
);

SET @add_route_fk_sql = IF(
  @route_fk_exists = 0,
  'ALTER TABLE bookings ADD CONSTRAINT fk_bookings_route_id FOREIGN KEY (route_id) REFERENCES routes (id) ON DELETE SET NULL ON UPDATE CASCADE',
  'SELECT 1'
);
PREPARE stmt_add_route_fk FROM @add_route_fk_sql;
EXECUTE stmt_add_route_fk;
DEALLOCATE PREPARE stmt_add_route_fk;

-- ---------------------------------------------------------------------------
-- Seed locations from airports + common destinations
-- ---------------------------------------------------------------------------
INSERT INTO locations (code, type, display_name, airport_id, is_active)
SELECT a.iata_code, 'AIRPORT', a.name, a.id, a.is_active
FROM airports a
WHERE a.deleted_at IS NULL
  AND NOT EXISTS (
    SELECT 1 FROM locations l WHERE l.code = a.iata_code AND l.deleted_at IS NULL
  );

INSERT INTO locations (code, type, display_name, is_active)
SELECT 'PATTAYA', 'CITY', 'Pattaya', 1
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM locations WHERE code = 'PATTAYA' AND deleted_at IS NULL);

INSERT INTO locations (code, type, display_name, is_active)
SELECT 'BANGKOK', 'CITY', 'Bangkok', 1
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM locations WHERE code = 'BANGKOK' AND deleted_at IS NULL);

-- ---------------------------------------------------------------------------
-- Seed route: BKK → PATTAYA (Airport Pickup)
-- ---------------------------------------------------------------------------
INSERT INTO routes (
  service_type_id, origin_location_id, destination_location_id,
  is_active, display_order
)
SELECT st.id, lo.id, ld.id, 1, 1
FROM service_types st
INNER JOIN locations lo ON lo.code = 'BKK' AND lo.deleted_at IS NULL
INNER JOIN locations ld ON ld.code = 'PATTAYA' AND ld.deleted_at IS NULL
WHERE st.code = 'AIRPORT_PICKUP'
  AND NOT EXISTS (
    SELECT 1
    FROM routes r
    WHERE r.service_type_id = st.id
      AND r.origin_location_id = lo.id
      AND r.destination_location_id = ld.id
      AND r.deleted_at IS NULL
  );

-- ---------------------------------------------------------------------------
-- Seed vehicle prices for BKK → PATTAYA route
-- ---------------------------------------------------------------------------
INSERT INTO vehicle_prices (route_id, vehicle_type_id, price, currency, is_active)
SELECT r.id, vt.id, 800.00, 'THB', 1
FROM routes r
INNER JOIN service_types st ON st.id = r.service_type_id AND st.code = 'AIRPORT_PICKUP'
INNER JOIN locations lo ON lo.id = r.origin_location_id AND lo.code = 'BKK'
INNER JOIN locations ld ON ld.id = r.destination_location_id AND ld.code = 'PATTAYA'
INNER JOIN vehicle_types vt ON vt.code = 'SEDAN'
WHERE NOT EXISTS (
  SELECT 1 FROM vehicle_prices vp
  WHERE vp.route_id = r.id AND vp.vehicle_type_id = vt.id AND vp.deleted_at IS NULL
);

INSERT INTO vehicle_prices (route_id, vehicle_type_id, price, currency, is_active)
SELECT r.id, vt.id, 1000.00, 'THB', 1
FROM routes r
INNER JOIN service_types st ON st.id = r.service_type_id AND st.code = 'AIRPORT_PICKUP'
INNER JOIN locations lo ON lo.id = r.origin_location_id AND lo.code = 'BKK'
INNER JOIN locations ld ON ld.id = r.destination_location_id AND ld.code = 'PATTAYA'
INNER JOIN vehicle_types vt ON vt.code = 'SUV'
WHERE NOT EXISTS (
  SELECT 1 FROM vehicle_prices vp
  WHERE vp.route_id = r.id AND vp.vehicle_type_id = vt.id AND vp.deleted_at IS NULL
);

INSERT INTO vehicle_prices (route_id, vehicle_type_id, price, currency, is_active)
SELECT r.id, vt.id, 1200.00, 'THB', 1
FROM routes r
INNER JOIN service_types st ON st.id = r.service_type_id AND st.code = 'AIRPORT_PICKUP'
INNER JOIN locations lo ON lo.id = r.origin_location_id AND lo.code = 'BKK'
INNER JOIN locations ld ON ld.id = r.destination_location_id AND ld.code = 'PATTAYA'
INNER JOIN vehicle_types vt ON vt.code = 'VIP_SUV'
WHERE NOT EXISTS (
  SELECT 1 FROM vehicle_prices vp
  WHERE vp.route_id = r.id AND vp.vehicle_type_id = vt.id AND vp.deleted_at IS NULL
);

INSERT INTO vehicle_prices (route_id, vehicle_type_id, price, currency, is_active)
SELECT r.id, vt.id, 1500.00, 'THB', 1
FROM routes r
INNER JOIN service_types st ON st.id = r.service_type_id AND st.code = 'AIRPORT_PICKUP'
INNER JOIN locations lo ON lo.id = r.origin_location_id AND lo.code = 'BKK'
INNER JOIN locations ld ON ld.id = r.destination_location_id AND ld.code = 'PATTAYA'
INNER JOIN vehicle_types vt ON vt.code = 'VAN'
WHERE NOT EXISTS (
  SELECT 1 FROM vehicle_prices vp
  WHERE vp.route_id = r.id AND vp.vehicle_type_id = vt.id AND vp.deleted_at IS NULL
);

INSERT INTO vehicle_prices (route_id, vehicle_type_id, price, currency, is_active)
SELECT r.id, vt.id, 1800.00, 'THB', 1
FROM routes r
INNER JOIN service_types st ON st.id = r.service_type_id AND st.code = 'AIRPORT_PICKUP'
INNER JOIN locations lo ON lo.id = r.origin_location_id AND lo.code = 'BKK'
INNER JOIN locations ld ON ld.id = r.destination_location_id AND ld.code = 'PATTAYA'
INNER JOIN vehicle_types vt ON vt.code = 'VIP_VAN'
WHERE NOT EXISTS (
  SELECT 1 FROM vehicle_prices vp
  WHERE vp.route_id = r.id AND vp.vehicle_type_id = vt.id AND vp.deleted_at IS NULL
);

INSERT INTO vehicle_prices (route_id, vehicle_type_id, price, currency, is_active)
SELECT r.id, vt.id, 2000.00, 'THB', 1
FROM routes r
INNER JOIN service_types st ON st.id = r.service_type_id AND st.code = 'AIRPORT_PICKUP'
INNER JOIN locations lo ON lo.id = r.origin_location_id AND lo.code = 'BKK'
INNER JOIN locations ld ON ld.id = r.destination_location_id AND ld.code = 'PATTAYA'
INNER JOIN vehicle_types vt ON vt.code = 'LUXURY'
WHERE NOT EXISTS (
  SELECT 1 FROM vehicle_prices vp
  WHERE vp.route_id = r.id AND vp.vehicle_type_id = vt.id AND vp.deleted_at IS NULL
);

-- ---------------------------------------------------------------------------
-- Seed charge policies (amounts only — no settings table usage)
-- ---------------------------------------------------------------------------
INSERT INTO charge_policies (charge_type, calculation_type, amount, is_active)
SELECT 'NAME_SIGN', 'FIXED', 100.00, 1
FROM DUAL
WHERE NOT EXISTS (
  SELECT 1 FROM charge_policies cp
  WHERE cp.charge_type = 'NAME_SIGN' AND cp.deleted_at IS NULL
);

INSERT INTO charge_policies (charge_type, calculation_type, amount, is_active)
SELECT 'NIGHT', 'PERCENT_OF_BASE', 15.00, 1
FROM DUAL
WHERE NOT EXISTS (
  SELECT 1 FROM charge_policies cp
  WHERE cp.charge_type = 'NIGHT' AND cp.deleted_at IS NULL
);

INSERT INTO charge_policies (charge_type, calculation_type, amount, is_active)
SELECT 'AIRPORT', 'FIXED', 50.00, 1
FROM DUAL
WHERE NOT EXISTS (
  SELECT 1 FROM charge_policies cp
  WHERE cp.charge_type = 'AIRPORT' AND cp.deleted_at IS NULL
);

-- ---------------------------------------------------------------------------
-- Restore booking_charge_items triggers (policy reference validation)
-- ---------------------------------------------------------------------------
DELIMITER $$

CREATE TRIGGER trg_bci_before_insert_validate
BEFORE INSERT ON booking_charge_items
FOR EACH ROW
BEGIN
  IF ABS(NEW.amount - ROUND(NEW.quantity * NEW.unit_price, 2)) > 0.009 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'booking_charge_items.amount must equal quantity * unit_price';
  END IF;

  IF NEW.reference_type = 'CHARGE_POLICY' THEN
    IF NEW.reference_id IS NULL THEN
      SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'CHARGE_POLICY reference requires reference_id';
    END IF;

    IF NOT EXISTS (
      SELECT 1
      FROM charge_policies cp
      WHERE cp.id = NEW.reference_id
        AND cp.deleted_at IS NULL
        AND cp.is_active = 1
    ) THEN
      SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Invalid or inactive charge_policies reference_id';
    END IF;
  END IF;

  IF NEW.reference_type = 'VEHICLE_PRICE' THEN
    IF NEW.reference_id IS NULL THEN
      SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'VEHICLE_PRICE reference requires reference_id';
    END IF;

    IF NOT EXISTS (
      SELECT 1
      FROM vehicle_prices vp
      WHERE vp.id = NEW.reference_id
        AND vp.deleted_at IS NULL
        AND vp.is_active = 1
    ) THEN
      SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Invalid or inactive vehicle_prices reference_id';
    END IF;
  END IF;
END$$

CREATE TRIGGER trg_bci_before_update_validate
BEFORE UPDATE ON booking_charge_items
FOR EACH ROW
BEGIN
  IF ABS(NEW.amount - ROUND(NEW.quantity * NEW.unit_price, 2)) > 0.009 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'booking_charge_items.amount must equal quantity * unit_price';
  END IF;

  IF NEW.reference_type = 'CHARGE_POLICY' THEN
    IF NEW.reference_id IS NULL THEN
      SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'CHARGE_POLICY reference requires reference_id';
    END IF;

    IF NOT EXISTS (
      SELECT 1
      FROM charge_policies cp
      WHERE cp.id = NEW.reference_id
        AND cp.deleted_at IS NULL
        AND cp.is_active = 1
    ) THEN
      SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Invalid or inactive charge_policies reference_id';
    END IF;
  END IF;

  IF NEW.reference_type = 'VEHICLE_PRICE' THEN
    IF NEW.reference_id IS NULL THEN
      SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'VEHICLE_PRICE reference requires reference_id';
    END IF;

    IF NOT EXISTS (
      SELECT 1
      FROM vehicle_prices vp
      WHERE vp.id = NEW.reference_id
        AND vp.deleted_at IS NULL
        AND vp.is_active = 1
    ) THEN
      SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Invalid or inactive vehicle_prices reference_id';
    END IF;
  END IF;
END$$

DELIMITER ;
