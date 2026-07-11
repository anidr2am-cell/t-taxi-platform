-- T-Ride Phase 2 — review feedback tags
-- Depends on: 18_reviews.sql
-- Apply against the target database explicitly, e.g.:
--   mysql -u USER -p tride_staging < database/35_review_tags.sql
-- Do not embed USE ttaxi or USE tride_staging here.

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

SET @schema := DATABASE();

SET @sql := (
  SELECT IF(
    EXISTS (
      SELECT 1
      FROM information_schema.COLUMNS
      WHERE TABLE_SCHEMA = @schema
        AND TABLE_NAME = 'reviews'
        AND COLUMN_NAME = 'tags_json'
    ),
    'SELECT 1',
    'ALTER TABLE reviews ADD COLUMN tags_json JSON NULL DEFAULT NULL AFTER comment'
  )
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;
