SELECT booking_id, COUNT(*) AS active_count
FROM booking_contact_connections
WHERE status IN ('PENDING','CONFIRM_REQUESTED','VERIFIED')
GROUP BY booking_id
HAVING COUNT(*) > 1;

SELECT IFNULL(MAX(active_count), 0) AS max_active_per_booking
FROM (
  SELECT booking_id, COUNT(*) AS active_count
  FROM booking_contact_connections
  WHERE status IN ('PENDING','CONFIRM_REQUESTED','VERIFIED')
  GROUP BY booking_id
) t;
