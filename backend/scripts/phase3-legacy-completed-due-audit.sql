-- Phase 3 Step 3 — read-only legacy COMPLETED+DUE audit (SELECT only)
-- Do not UPDATE/DELETE. Ops review only.

SET NAMES utf8mb4;

SELECT COUNT(*) AS legacy_completed_due_count
  FROM bookings b
 WHERE b.deleted_at IS NULL
   AND b.is_archived = 0
   AND b.status = 'COMPLETED'
   AND b.commission_status = 'DUE';

SELECT b.booking_number,
       b.commission_status,
       b.commission_amount,
       b.commission_paid_at,
       b.completed_at,
       b.created_at
  FROM bookings b
 WHERE b.deleted_at IS NULL
   AND b.is_archived = 0
   AND b.status = 'COMPLETED'
   AND b.commission_status = 'DUE'
 ORDER BY b.completed_at DESC
 LIMIT 20;
