USE ttaxi;

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS notification_rules (
  id INT UNSIGNED NOT NULL AUTO_INCREMENT,
  event_type VARCHAR(50) NOT NULL,
  recipient_role ENUM('CUSTOMER', 'DRIVER', 'ADMIN', 'SYSTEM') NOT NULL,
  channel ENUM('PUSH', 'EMAIL', 'SMS', 'IN_APP') NOT NULL,
  template_key VARCHAR(150) NULL DEFAULT NULL,
  priority INT NOT NULL DEFAULT 0,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  created_by BIGINT UNSIGNED NULL DEFAULT NULL,
  updated_by BIGINT UNSIGNED NULL DEFAULT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at DATETIME NULL DEFAULT NULL,
  PRIMARY KEY (id),
  KEY idx_notification_rules_event (event_type, is_active, priority),
  KEY idx_notification_rules_recipient (recipient_role, channel),
  CONSTRAINT fk_notification_rules_created_by
    FOREIGN KEY (created_by) REFERENCES users (id)
    ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT fk_notification_rules_updated_by
    FOREIGN KEY (updated_by) REFERENCES users (id)
    ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS outbox_events (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  aggregate_type VARCHAR(50) NOT NULL,
  aggregate_id BIGINT UNSIGNED NOT NULL,
  event_type VARCHAR(50) NOT NULL,
  payload JSON NOT NULL,
  status ENUM('PENDING', 'PROCESSING', 'COMPLETED', 'FAILED') NOT NULL DEFAULT 'PENDING',
  retry_count INT UNSIGNED NOT NULL DEFAULT 0,
  max_retries INT UNSIGNED NOT NULL DEFAULT 3,
  scheduled_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  processed_at DATETIME NULL DEFAULT NULL,
  error_message VARCHAR(500) NULL DEFAULT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_outbox_events_status_scheduled (status, scheduled_at),
  KEY idx_outbox_events_aggregate (aggregate_type, aggregate_id),
  KEY idx_outbox_events_event_type (event_type)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

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

ALTER TABLE booking_charge_items
  MODIFY COLUMN charge_type ENUM(
    'VEHICLE_BASE',
    'NAME_SIGN',
    'NIGHT_SURCHARGE',
    'AIRPORT_PARKING',
    'AIRPORT_SURCHARGE',
    'TOLL_GATE',
    'PROMOTION',
    'COUPON',
    'DRIVER_EXTRA',
    'SEASON_SURCHARGE',
    'HOLIDAY_SURCHARGE',
    'WAITING_CHARGE',
    'OTHER'
  ) NOT NULL;

UPDATE booking_charge_items
SET charge_type = 'AIRPORT_SURCHARGE'
WHERE charge_type = 'AIRPORT_PARKING';

ALTER TABLE booking_charge_items
  MODIFY COLUMN charge_type ENUM(
    'VEHICLE_BASE',
    'NAME_SIGN',
    'NIGHT_SURCHARGE',
    'AIRPORT_SURCHARGE',
    'TOLL_GATE',
    'PROMOTION',
    'COUPON',
    'DRIVER_EXTRA',
    'SEASON_SURCHARGE',
    'HOLIDAY_SURCHARGE',
    'WAITING_CHARGE',
    'OTHER'
  ) NOT NULL;

ALTER TABLE charge_policies
  MODIFY COLUMN charge_type ENUM(
    'VEHICLE_BASE',
    'NAME_SIGN',
    'NIGHT_SURCHARGE',
    'AIRPORT_PARKING',
    'AIRPORT_SURCHARGE',
    'TOLL_GATE',
    'PROMOTION',
    'COUPON',
    'DRIVER_EXTRA',
    'SEASON_SURCHARGE',
    'HOLIDAY_SURCHARGE',
    'WAITING_CHARGE',
    'OTHER'
  ) NOT NULL;

UPDATE charge_policies
SET charge_type = 'AIRPORT_SURCHARGE'
WHERE charge_type = 'AIRPORT_PARKING';

ALTER TABLE charge_policies
  MODIFY COLUMN charge_type ENUM(
    'VEHICLE_BASE',
    'NAME_SIGN',
    'NIGHT_SURCHARGE',
    'AIRPORT_SURCHARGE',
    'TOLL_GATE',
    'PROMOTION',
    'COUPON',
    'DRIVER_EXTRA',
    'SEASON_SURCHARGE',
    'HOLIDAY_SURCHARGE',
    'WAITING_CHARGE',
    'OTHER'
  ) NOT NULL;

ALTER TABLE charge_policies
  MODIFY COLUMN modifier_type ENUM(
    'FIXED',
    'PERCENT_OF_BASE',
    'PERCENT_OF_SUBTOTAL'
  ) NOT NULL DEFAULT 'FIXED';
