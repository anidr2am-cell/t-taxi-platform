SELECT COUNT(*) AS commission_receipt_files
FROM files
WHERE entity_type = 'COMMISSION_RECEIPT'
  AND deleted_at IS NULL;

SELECT b.booking_number, b.commission_receipt_file_id, f.id AS file_id, f.file_path, f.deleted_at
FROM bookings b
LEFT JOIN files f ON f.id = b.commission_receipt_file_id
WHERE b.commission_receipt_file_id IS NOT NULL
  AND b.deleted_at IS NULL
ORDER BY b.id DESC
LIMIT 50;

SELECT b.booking_number, COUNT(*) AS receipt_file_count
FROM bookings b
INNER JOIN files f ON f.entity_id = b.id AND f.entity_type = 'COMMISSION_RECEIPT' AND f.deleted_at IS NULL
WHERE b.deleted_at IS NULL
GROUP BY b.id, b.booking_number
HAVING COUNT(*) > 1;

SELECT f.id, f.file_path, f.entity_id, f.deleted_at
FROM files f
LEFT JOIN bookings b ON b.id = f.entity_id AND b.commission_receipt_file_id = f.id
WHERE f.entity_type = 'COMMISSION_RECEIPT'
  AND f.deleted_at IS NULL
  AND (b.id IS NULL OR b.commission_receipt_file_id IS NULL OR b.commission_receipt_file_id <> f.id)
LIMIT 50;
