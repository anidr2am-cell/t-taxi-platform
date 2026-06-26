-- TTaxi Platform — Identity domain (MySQL 8)
-- Depends on: 00_database.sql

USE ttaxi;

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- users
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS users (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  email VARCHAR(255) NOT NULL,
  password_hash VARCHAR(255) NULL DEFAULT NULL,
  role ENUM('CUSTOMER', 'DRIVER', 'ADMIN', 'SUPER_ADMIN') NOT NULL DEFAULT 'CUSTOMER',
  phone VARCHAR(30) NULL DEFAULT NULL,
  phone_country_code VARCHAR(5) NULL DEFAULT NULL,
  country_code CHAR(2) NULL DEFAULT NULL,
  locale VARCHAR(10) NOT NULL DEFAULT 'ko',
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  email_verified_at DATETIME NULL DEFAULT NULL,
  last_login_at DATETIME NULL DEFAULT NULL,
  email_active VARCHAR(255) GENERATED ALWAYS AS (
    IF(deleted_at IS NULL, email, NULL)
  ) STORED,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at DATETIME NULL DEFAULT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_users_email_active (email_active),
  KEY idx_users_role_active (role, is_active),
  KEY idx_users_phone (phone)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- user_profiles
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS user_profiles (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id BIGINT UNSIGNED NOT NULL,
  display_name VARCHAR(100) NULL DEFAULT NULL,
  avatar_url VARCHAR(512) NULL DEFAULT NULL,
  birth_date DATE NULL DEFAULT NULL,
  gender ENUM('M', 'F', 'O', 'N') NULL DEFAULT NULL,
  marketing_opt_in TINYINT(1) NOT NULL DEFAULT 0,
  notes TEXT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at DATETIME NULL DEFAULT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_user_profiles_user_id (user_id),
  CONSTRAINT fk_user_profiles_user_id
    FOREIGN KEY (user_id) REFERENCES users (id)
    ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
