ALTER TABLE users
  ADD COLUMN IF NOT EXISTS auth_token_version INT UNSIGNED NOT NULL DEFAULT 0
  AFTER password_hash;

CREATE TABLE IF NOT EXISTS driver_password_reset_codes (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id BIGINT UNSIGNED NOT NULL,
  code_hash CHAR(64) NOT NULL,
  expires_at DATETIME NOT NULL,
  failed_attempts TINYINT UNSIGNED NOT NULL DEFAULT 0,
  used_at DATETIME NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_driver_password_reset_user_active (user_id, used_at, expires_at),
  CONSTRAINT fk_driver_password_reset_user
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
