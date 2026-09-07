-- users.phone UNIQUE constraint (NULL values remain allowed; multiple NULLs OK)
-- Depends on: users table (01_identity.sql)
-- Additive + rerunnable.

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

DROP PROCEDURE IF EXISTS sp_apply_users_phone_unique;

DELIMITER $$

CREATE PROCEDURE sp_apply_users_phone_unique()
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.STATISTICS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 'users'
      AND INDEX_NAME = 'idx_users_phone'
      AND NON_UNIQUE = 1
  ) THEN
    ALTER TABLE users DROP INDEX idx_users_phone;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.STATISTICS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 'users'
      AND INDEX_NAME = 'uk_users_phone'
  ) THEN
    ALTER TABLE users ADD UNIQUE INDEX uk_users_phone (phone);
  END IF;
END$$

DELIMITER ;

CALL sp_apply_users_phone_unique();

DROP PROCEDURE IF EXISTS sp_apply_users_phone_unique;
