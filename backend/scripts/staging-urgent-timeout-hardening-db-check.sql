-- Phase 3 Step 4 — read-only durable state check for one E2E booking.
-- Replace @BOOKING_NUMBER@ before execution.

SELECT
  b.booking_number,
  b.status AS booking_status,
  b.urgent_negotiation_id AS current_negotiation_id,
  n.id AS negotiation_id,
  n.status AS negotiation_status,
  n.attempt_count,
  n.locked_driver_id,
  (
    SELECT bua.outcome
    FROM booking_urgent_negotiation_attempts bua
    WHERE bua.negotiation_id = n.id
    ORDER BY bua.attempt_number DESC
    LIMIT 1
  ) AS latest_attempt_outcome,
  (
    SELECT COUNT(*)
    FROM booking_driver_assignments bda
    WHERE bda.booking_id = b.id
      AND bda.is_active = 1
      AND bda.deleted_at IS NULL
  ) AS active_assignment_count,
  (
    SELECT bda.status
    FROM booking_driver_assignments bda
    WHERE bda.booking_id = b.id
      AND bda.deleted_at IS NULL
    ORDER BY bda.id DESC
    LIMIT 1
  ) AS latest_assignment_status,
  (
    SELECT bda.assignment_reason
    FROM booking_driver_assignments bda
    WHERE bda.booking_id = b.id
      AND bda.deleted_at IS NULL
    ORDER BY bda.id DESC
    LIMIT 1
  ) AS latest_assignment_reason
FROM bookings b
LEFT JOIN booking_urgent_negotiations n ON n.id = b.urgent_negotiation_id
WHERE b.booking_number = '@BOOKING_NUMBER@'
  AND b.deleted_at IS NULL;

SELECT
  bun.id AS negotiation_id,
  bun.status AS negotiation_status,
  bun.attempt_count,
  bun.locked_driver_id,
  (
    SELECT bua.outcome
    FROM booking_urgent_negotiation_attempts bua
    WHERE bua.negotiation_id = bun.id
    ORDER BY bua.attempt_number DESC
    LIMIT 1
  ) AS latest_attempt_outcome
FROM booking_urgent_negotiations bun
JOIN bookings b ON b.id = bun.booking_id
WHERE b.booking_number = '@BOOKING_NUMBER@'
ORDER BY bun.id;
