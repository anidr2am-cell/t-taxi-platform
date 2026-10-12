# Settlement timestamp migration 69

This runbook applies `database/69_settlement_timestamps_bangkok.sql`. It moves
the 52 verified legacy `commission_paid_at` values from UTC wall-clock to the
project's Asia/Bangkok `DATETIME` contract.

## Required preflight

1. Take the production database and upload backups and record their SHA-256
   checksums.
2. Build the new backend image before the maintenance window, without replacing
   the running container.
3. Run the candidate `SELECT` below. Continue only when `target_count = 52`.
   A different count requires a new review; do not apply the migration.

```sql
SELECT COUNT(*) AS target_count
FROM bookings
WHERE commission_paid_at IS NOT NULL
  AND (
    (
      JSON_UNQUOTE(JSON_EXTRACT(metadata, '$.commissionApprovedAt')) REGEXP 'Z$'
      AND ABS(TIMESTAMPDIFF(SECOND, commission_paid_at,
        STR_TO_DATE(LEFT(REPLACE(JSON_UNQUOTE(JSON_EXTRACT(metadata,
          '$.commissionApprovedAt')), 'T', ' '), 19), '%Y-%m-%d %H:%i:%s'))) <= 2
    )
    OR booking_number IN (
      'TX202607090005',
      'TX202607110002',
      'TX202607110003',
      'TX202607120002',
      'TX202607130002'
    )
  );
```

## Short maintenance window

Settlement approval and trip completion use the same backend. To prevent the
old backend from writing another UTC value after the migration selection, use a
short backend-only maintenance window:

1. Stop only `tride-prod-backend`. Do not stop the database, frontend, or proxy,
   and do not use `docker compose down`.
2. Confirm no application transaction remains for the production database:

```sql
SELECT COUNT(*) AS active_application_transactions
FROM information_schema.innodb_trx t
JOIN information_schema.processlist p ON p.ID = t.trx_mysql_thread_id
WHERE p.DB = DATABASE()
  AND p.USER <> 'root';
```

   Continue only when the result is `0`. This covers in-flight receipt approval
   and trip-completion requests after the backend has stopped accepting work.
3. Re-run the target-count query and require exactly `52`.
4. Apply migration 69 and verify that the backup table contains exactly 52 rows.
5. Start the prebuilt backend image and require health/readiness success before
   ending the maintenance window.

If any check fails, leave the old backend image available, do not start the new
write path, and restore service according to the deployment rollback plan.
