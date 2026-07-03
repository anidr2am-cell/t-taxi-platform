-- Driver application intake for admin-reviewed DRIVER onboarding.
-- Depends on: 00_database.sql, 01_identity.sql, 03_fleet_places.sql
-- Rerunnable migration: creates the table when missing and leaves existing data untouched.

USE ttaxi;

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS driver_applications (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  application_number VARCHAR(32) NOT NULL,
  status ENUM('PENDING', 'APPROVED', 'REJECTED') NOT NULL DEFAULT 'PENDING',
  email VARCHAR(255) NOT NULL,
  password_hash VARCHAR(255) NULL DEFAULT NULL,
  full_name VARCHAR(100) NOT NULL,
  phone VARCHAR(30) NOT NULL,
  phone_country_code VARCHAR(5) NULL DEFAULT NULL,
  country_code CHAR(2) NULL DEFAULT NULL,
  locale VARCHAR(10) NOT NULL DEFAULT 'ko',
  driving_license_number VARCHAR(50) NOT NULL,
  driving_license_country CHAR(2) NULL DEFAULT NULL,
  driving_license_expiry_date DATE NULL DEFAULT NULL,
  years_of_driving_experience TINYINT UNSIGNED NOT NULL DEFAULT 0,
  vehicle_ownership_type ENUM('OWNED', 'RENTED', 'COMPANY', 'OTHER') NOT NULL,
  vehicle_type_code VARCHAR(30) NOT NULL,
  vehicle_make VARCHAR(50) NULL DEFAULT NULL,
  vehicle_model VARCHAR(100) NULL DEFAULT NULL,
  vehicle_year SMALLINT UNSIGNED NULL DEFAULT NULL,
  vehicle_color VARCHAR(30) NULL DEFAULT NULL,
  vehicle_plate_number VARCHAR(20) NOT NULL,
  service_areas JSON NOT NULL,
  languages JSON NULL DEFAULT NULL,
  notes TEXT NULL,
  personal_data_consent_at DATETIME NOT NULL,
  driver_terms_consent_at DATETIME NOT NULL,
  status_lookup_token_hash CHAR(64) NOT NULL,
  rejection_reason TEXT NULL,
  admin_note TEXT NULL,
  submitted_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  reviewed_at DATETIME NULL DEFAULT NULL,
  reviewed_by BIGINT UNSIGNED NULL DEFAULT NULL,
  approved_user_id BIGINT UNSIGNED NULL DEFAULT NULL,
  approved_driver_id BIGINT UNSIGNED NULL DEFAULT NULL,
  resubmitted_from_application_id BIGINT UNSIGNED NULL DEFAULT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at DATETIME NULL DEFAULT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_driver_applications_number (application_number),
  KEY idx_driver_applications_status (status),
  KEY idx_driver_applications_submitted_at (submitted_at),
  KEY idx_driver_applications_email (email),
  KEY idx_driver_applications_plate (vehicle_plate_number),
  KEY idx_driver_applications_reviewed_by (reviewed_by),
  KEY idx_driver_applications_approved_user (approved_user_id),
  KEY idx_driver_applications_approved_driver (approved_driver_id),
  KEY idx_driver_applications_resubmitted_from (resubmitted_from_application_id),
  CONSTRAINT fk_driver_applications_reviewed_by
    FOREIGN KEY (reviewed_by) REFERENCES users (id)
    ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT fk_driver_applications_approved_user_id
    FOREIGN KEY (approved_user_id) REFERENCES users (id)
    ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT fk_driver_applications_approved_driver_id
    FOREIGN KEY (approved_driver_id) REFERENCES drivers (id)
    ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT fk_driver_applications_resubmitted_from
    FOREIGN KEY (resubmitted_from_application_id) REFERENCES driver_applications (id)
    ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT chk_driver_applications_service_areas_json
    CHECK (JSON_VALID(service_areas)),
  CONSTRAINT chk_driver_applications_languages_json
    CHECK (languages IS NULL OR JSON_VALID(languages))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
