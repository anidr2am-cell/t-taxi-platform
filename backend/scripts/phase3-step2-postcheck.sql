SELECT TABLE_NAME
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME = 'settlement_receipt_idempotency';

SELECT INDEX_NAME, COLUMN_NAME, SEQ_IN_INDEX
FROM information_schema.STATISTICS
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME = 'settlement_receipt_idempotency'
  AND INDEX_NAME = 'uk_settlement_receipt_idempotency_scope'
ORDER BY SEQ_IN_INDEX;

SELECT COUNT(*) AS expired_pending_rows
FROM settlement_receipt_idempotency
WHERE expires_at < UTC_TIMESTAMP()
  AND status = 'PENDING';
