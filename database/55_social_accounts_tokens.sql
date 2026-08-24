-- Persist Kakao (and future LINE) OAuth tokens on social_accounts for ongoing API use.
-- Depends on: 54_social_accounts.sql
-- GOOGLE rows may keep these columns NULL (one-shot ID token flow).
-- Safe to re-run when columns already exist.

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

SET @access_token_exists = (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'social_accounts'
    AND COLUMN_NAME = 'access_token'
);

SET @sql = IF(
  @access_token_exists = 0,
  'ALTER TABLE social_accounts ADD COLUMN access_token TEXT NULL DEFAULT NULL AFTER provider_email',
  'SELECT 1'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @refresh_token_exists = (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'social_accounts'
    AND COLUMN_NAME = 'refresh_token'
);

SET @sql = IF(
  @refresh_token_exists = 0,
  'ALTER TABLE social_accounts ADD COLUMN refresh_token TEXT NULL DEFAULT NULL AFTER access_token',
  'SELECT 1'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @token_expires_at_exists = (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'social_accounts'
    AND COLUMN_NAME = 'token_expires_at'
);

SET @sql = IF(
  @token_expires_at_exists = 0,
  'ALTER TABLE social_accounts ADD COLUMN token_expires_at DATETIME NULL DEFAULT NULL AFTER refresh_token',
  'SELECT 1'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;
