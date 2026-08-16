-- Phase 3 Step 4 read-only audit
-- URGENT timeout worker / stale negotiation investigation (SELECT only).
-- Lock window: 3 MIN (hardcoded). Customer decision: 2 MIN (hardcoded). MAX_ATTEMPTS: 3.

-- A. OPEN urgent bookings in BROADCASTING (no pure-BROADCASTING worker TTL in code)
SELECT b.id, b.booking_number, b.status, b.created_at, b.scheduled_pickup_at,
       n.id AS negotiation_id, n.status AS negotiation_status, n.attempt_count,
       n.created_at AS negotiation_created_at, n.updated_at AS negotiation_updated_at,
       TIMESTAMPDIFF(MINUTE, n.updated_at, UTC_TIMESTAMP(3)) AS minutes_since_negotiation_update
FROM bookings b
JOIN booking_urgent_negotiations n ON n.id = b.urgent_negotiation_id
WHERE b.deleted_at IS NULL AND b.is_archived = 0
  AND b.is_urgent_request = 1 AND b.status = 'OPEN'
  AND n.status = 'BROADCASTING'
ORDER BY n.updated_at ASC;

-- B1. BROADCASTING/OPEN with active assignment (should be empty)
SELECT b.booking_number, b.status, n.status AS neg_status, bda.id AS assignment_id
FROM bookings b
JOIN booking_urgent_negotiations n ON n.id = b.urgent_negotiation_id
JOIN booking_driver_assignments bda ON bda.booking_id = b.id
  AND bda.is_active = 1 AND bda.deleted_at IS NULL
WHERE b.is_urgent_request = 1 AND n.status = 'BROADCASTING';

-- B2. CONFIRMED negotiation but booking still OPEN
SELECT b.booking_number, b.status, n.status, n.closed_reason
FROM bookings b
JOIN booking_urgent_negotiations n ON n.id = b.urgent_negotiation_id
WHERE b.is_urgent_request = 1 AND b.status = 'OPEN' AND n.status = 'CONFIRMED';

-- B3. Worker candidates right now
SELECT n.id, b.booking_number, n.status, n.lock_expires_at, n.customer_decision_expires_at
FROM booking_urgent_negotiations n
JOIN bookings b ON b.id = n.booking_id
WHERE b.deleted_at IS NULL AND b.is_archived = 0
  AND (
    (n.status = 'LOCKED' AND n.lock_expires_at <= UTC_TIMESTAMP(3))
    OR (n.status = 'AWAITING_CUSTOMER' AND n.customer_decision_expires_at <= UTC_TIMESTAMP(3))
  );

-- C. Duplicate BROADCASTING rows per booking (should be 0)
SELECT booking_id, COUNT(*) AS cnt
FROM booking_urgent_negotiations
WHERE status = 'BROADCASTING'
GROUP BY booking_id HAVING cnt > 1;

-- D. OPEN urgent with active assignment (open-call visibility conflict)
SELECT b.booking_number, b.status, n.status AS neg_status, bda.id AS active_assignment_id
FROM bookings b
JOIN booking_urgent_negotiations n ON n.id = b.urgent_negotiation_id
JOIN booking_driver_assignments bda ON bda.booking_id = b.id
  AND bda.is_active = 1 AND bda.deleted_at IS NULL
WHERE b.deleted_at IS NULL AND b.is_archived = 0
  AND b.is_urgent_request = 1 AND b.status = 'OPEN';

-- E. Timestamp / state inconsistencies
SELECT b.booking_number, n.status,
       n.locked_at, n.lock_expires_at,
       n.customer_decision_expires_at, n.closed_at,
       CASE
         WHEN n.status = 'LOCKED' AND n.lock_expires_at IS NULL THEN 'LOCKED_MISSING_EXPIRY'
         WHEN n.status = 'AWAITING_CUSTOMER' AND n.customer_decision_expires_at IS NULL THEN 'AWAITING_MISSING_EXPIRY'
         WHEN n.status = 'BROADCASTING' AND n.locked_driver_id IS NOT NULL THEN 'BROADCASTING_HAS_LOCK'
         WHEN n.status IN ('CONFIRMED','CANCELLED') AND n.closed_at IS NULL THEN 'CLOSED_MISSING_CLOSED_AT'
       END AS inconsistency
FROM bookings b
JOIN booking_urgent_negotiations n ON n.id = b.urgent_negotiation_id
WHERE b.is_urgent_request = 1 AND b.deleted_at IS NULL AND b.is_archived = 0
HAVING inconsistency IS NOT NULL;
