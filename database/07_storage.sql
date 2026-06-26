-- TTaxi Platform — File storage (MySQL 8)
-- Depends on: 00_database.sql through 05_chat.sql

USE ttaxi;

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- files
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS files (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  entity_type VARCHAR(30) NOT NULL,
  entity_id BIGINT UNSIGNED NOT NULL,
  storage_provider ENUM('LOCAL', 'S3') NOT NULL DEFAULT 'LOCAL',
  file_path VARCHAR(512) NOT NULL,
  file_url VARCHAR(1024) NULL DEFAULT NULL,
  mime_type VARCHAR(100) NULL DEFAULT NULL,
  file_size BIGINT UNSIGNED NULL DEFAULT NULL,
  original_filename VARCHAR(255) NULL DEFAULT NULL,
  uploaded_by_user_id BIGINT UNSIGNED NULL DEFAULT NULL,
  created_by BIGINT UNSIGNED NULL DEFAULT NULL,
  updated_by BIGINT UNSIGNED NULL DEFAULT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at DATETIME NULL DEFAULT NULL,
  PRIMARY KEY (id),
  KEY idx_files_entity (entity_type, entity_id),
  CONSTRAINT fk_files_uploaded_by_user_id
    FOREIGN KEY (uploaded_by_user_id) REFERENCES users (id)
    ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT fk_files_created_by
    FOREIGN KEY (created_by) REFERENCES users (id)
    ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT fk_files_updated_by
    FOREIGN KEY (updated_by) REFERENCES users (id)
    ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
