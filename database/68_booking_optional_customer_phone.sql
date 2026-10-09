-- Allow KakaoTalk and LINE customers to book without a telephone number.
-- WhatsApp and SMS bookings continue to persist an international number.
SET @customer_phone_nullable = (
  SELECT IS_NULLABLE
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'bookings'
    AND COLUMN_NAME = 'customer_phone'
  LIMIT 1
);

SET @make_customer_phone_nullable_sql = IF(
  @customer_phone_nullable = 'NO',
  'ALTER TABLE bookings MODIFY COLUMN customer_phone VARCHAR(30) NULL DEFAULT NULL',
  'SELECT 1'
);

PREPARE make_customer_phone_nullable_stmt FROM @make_customer_phone_nullable_sql;
EXECUTE make_customer_phone_nullable_stmt;
DEALLOCATE PREPARE make_customer_phone_nullable_stmt;
