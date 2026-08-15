-- Read-only classification of stale active assignments for E2E driver (driver_id=11).
SELECT COUNT(*) AS stale_active_assignments
FROM booking_driver_assignments bda
INNER JOIN bookings b ON b.id = bda.booking_id AND b.deleted_at IS NULL
WHERE bda.driver_id = 11
  AND bda.is_active = 1
  AND bda.deleted_at IS NULL
  AND b.is_archived = 0
  AND b.status IN ('DRIVER_ASSIGNED', 'ON_ROUTE', 'DRIVER_ARRIVED', 'PICKED_UP', 'SETTLEMENT_PENDING');

SELECT b.booking_number,
       b.status,
       b.is_archived,
       bda.assignment_reason,
       bda.status AS assignment_status,
       b.customer_name
FROM booking_driver_assignments bda
INNER JOIN bookings b ON b.id = bda.booking_id AND b.deleted_at IS NULL
WHERE bda.driver_id = 11
  AND bda.is_active = 1
  AND bda.deleted_at IS NULL
  AND b.is_archived = 0
ORDER BY b.booking_number DESC
LIMIT 100;

SELECT COUNT(*) AS non_e2e_active_assignments
FROM booking_driver_assignments bda
INNER JOIN bookings b ON b.id = bda.booking_id AND b.deleted_at IS NULL
WHERE bda.driver_id = 11
  AND bda.is_active = 1
  AND bda.deleted_at IS NULL
  AND b.is_archived = 0
  AND (b.customer_name IS NULL OR b.customer_name NOT LIKE '[E2E]%');

SELECT b.booking_number,
       b.status,
       b.is_archived,
       b.special_requests,
       b.customer_name
FROM bookings b
WHERE b.booking_number = 'TX202608150013'
  AND b.deleted_at IS NULL;
