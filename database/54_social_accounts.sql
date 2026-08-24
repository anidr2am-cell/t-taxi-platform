-- Social login provider linkage (Google first; KAKAO/LINE reserved).
-- Depends on: 01_identity.sql
-- Additive + rerunnable.

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

SET @social_accounts_exists = (
  SELECT COUNT(*)
  FROM information_schema.TABLES
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'social_accounts'
);

SET @create_social_accounts_sql = IF(
  @social_accounts_exists = 0,
  'CREATE TABLE social_accounts (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    user_id BIGINT UNSIGNED NOT NULL,
    provider ENUM(''GOOGLE'', ''KAKAO'', ''LINE'') NOT NULL,
    provider_user_id VARCHAR(255) NOT NULL,
    provider_email VARCHAR(255) NULL DEFAULT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uk_social_accounts_provider_user (provider, provider_user_id),
    KEY idx_social_accounts_user_id (user_id),
    CONSTRAINT fk_social_accounts_user_id
      FOREIGN KEY (user_id) REFERENCES users (id)
      ON DELETE CASCADE ON UPDATE CASCADE
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci',
  'SELECT 1'
);

PREPARE create_social_accounts_stmt FROM @create_social_accounts_sql;
EXECUTE create_social_accounts_stmt;
DEALLOCATE PREPARE create_social_accounts_stmt;
