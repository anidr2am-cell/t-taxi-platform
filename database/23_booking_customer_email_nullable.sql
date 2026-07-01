-- Allow guest bookings without a customer email snapshot.
-- Rerunnable migration: only alters column when still NOT NULL.

USE ttaxi;

SET @schema := DATABASE();

SET @sql := (
  SELECT IF(
    EXISTS (
      SELECT 1
      FROM INFORMATION_SCHEMA.COLUMNS
      WHERE TABLE_SCHEMA = @schema
        AND TABLE_NAME = 'bookings'
        AND COLUMN_NAME = 'customer_email'
        AND IS_NULLABLE = 'NO'
    ),
    'ALTER TABLE bookings MODIFY COLUMN customer_email VARCHAR(255) NULL DEFAULT NULL',
    'SELECT 1'
  )
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;
