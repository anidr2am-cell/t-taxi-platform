-- Support inquiry intake for customer center MVP.
-- Rerunnable migration: creates tables when missing and preserves existing data.

USE ttaxi;

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS support_inquiries (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  public_id VARCHAR(32) NOT NULL,
  customer_name VARCHAR(100) NULL DEFAULT NULL,
  customer_phone VARCHAR(30) NULL DEFAULT NULL,
  customer_email VARCHAR(255) NULL DEFAULT NULL,
  message TEXT NOT NULL,
  status ENUM('NEW', 'IN_PROGRESS', 'RESOLVED', 'CLOSED') NOT NULL DEFAULT 'NEW',
  source VARCHAR(30) NOT NULL DEFAULT 'WEB_SUPPORT',
  locale VARCHAR(10) NULL DEFAULT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at DATETIME NULL DEFAULT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_support_inquiries_public_id (public_id),
  KEY idx_support_inquiries_status (status),
  KEY idx_support_inquiries_created_at (created_at),
  KEY idx_support_inquiries_deleted_at (deleted_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS support_inquiry_attachments (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  inquiry_id BIGINT UNSIGNED NOT NULL,
  original_file_name VARCHAR(255) NULL DEFAULT NULL,
  mime_type VARCHAR(100) NULL DEFAULT NULL,
  file_size BIGINT UNSIGNED NULL DEFAULT NULL,
  storage_path VARCHAR(500) NULL DEFAULT NULL,
  public_url VARCHAR(500) NULL DEFAULT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_support_inquiry_attachments_inquiry_id (inquiry_id),
  CONSTRAINT fk_support_inquiry_attachments_inquiry
    FOREIGN KEY (inquiry_id) REFERENCES support_inquiries (id)
    ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
