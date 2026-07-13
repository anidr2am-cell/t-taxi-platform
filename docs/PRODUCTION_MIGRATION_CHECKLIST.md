# T-Ride Production Migration Checklist

This checklist covers the current production candidate migrations only.

Official order:

1. `database/35_review_tags.sql`
2. `database/36_admin_booking_notes.sql`
3. `database/37_add_settlement_pending_booking_status.sql`

Do not run the full migration runner against an existing production database.
Apply only reviewed missing SQL files against the explicitly selected production
T-Ride database.

## Global pre-check

Before any SQL is applied:

- Confirm target DB name with the deployment owner.
- Confirm the DB is not legacy `ttaxi`, KTaxi, staging, or a copied staging DB.
- Confirm current Git HEAD and SQL file checksums.
- Create and verify a full DB backup.
- Confirm restore procedure and backup location.
- Check active traffic and choose a maintenance window if lock risk exists.
- Capture current table definitions for affected tables.
- Capture current enum definitions for affected columns.

## Migration 35: `database/35_review_tags.sql`

Purpose:

- Add support for storing customer review tags.

Pre-check:

- Confirm `reviews` table exists.
- Confirm whether `reviews.tags_json` already exists.
- Confirm no incompatible column with the same purpose already exists.

Backup required:

- Yes. A full DB backup is required before applying.

Expected lock:

- Low to moderate depending on `reviews` table size and MariaDB ALTER behavior.

Execution order:

- Run after global pre-check.
- Run before migrations 36 and 37.

Post-check:

- Confirm `reviews.tags_json` exists.
- Confirm existing reviews are still readable.
- Confirm a review with rating/comment/tags can be queried.

Rollback idea:

- Prefer restoring from backup if production data was affected.
- If approved and safe, remove only the newly added column after confirming no
  production reviews depend on it.

## Migration 36: `database/36_admin_booking_notes.sql`

Purpose:

- Create admin-only booking notes storage.

Pre-check:

- Confirm `bookings` table exists.
- Confirm admin/user reference tables expected by the SQL exist.
- Confirm `admin_booking_notes` does not already exist with a conflicting
  schema.

Backup required:

- Yes. A full DB backup is required before applying.

Expected lock:

- Low for table creation, but foreign key validation should still be reviewed.

Execution order:

- Run after migration 35.
- Run before migration 37.

Post-check:

- Confirm `admin_booking_notes` table exists.
- Confirm indexes and foreign keys exist.
- Confirm admin booking detail pages still load.

Rollback idea:

- If no production notes have been created, drop the new table only after owner
  approval.
- If notes exist, restore from backup or migrate the notes before rollback.

## Migration 37: `database/37_add_settlement_pending_booking_status.sql`

Purpose:

- Add `SETTLEMENT_PENDING` to booking status enums used by:
  - `bookings.status`
  - `booking_status_logs.from_status`
  - `booking_status_logs.to_status`

Pre-check:

- Confirm `bookings` and `booking_status_logs` tables exist.
- Capture current enum values for the three columns.
- Confirm whether `SETTLEMENT_PENDING` already exists.
- Confirm no unexpected status values exist in data.

Backup required:

- Yes. This migration changes status enum definitions and must have a verified
  backup first.

Expected lock:

- Moderate. Enum ALTER operations may lock affected tables depending on table
  size and MariaDB behavior.

Execution order:

- Run after migrations 35 and 36.

Post-check:

- Confirm all three enum columns include `SETTLEMENT_PENDING`.
- Confirm existing booking statuses are unchanged.
- Confirm settlement pending bookings can be queried.
- Confirm booking status logs can store transitions into and out of
  `SETTLEMENT_PENDING`.

Rollback idea:

- Avoid enum rollback while any row uses `SETTLEMENT_PENDING`.
- If rollback is unavoidable, move affected rows to an approved previous status,
  record the operational impact, and restore from backup if data integrity is in
  doubt.

## Global post-check

After all approved migrations:

- Re-check affected table definitions.
- Run minimal backend health check.
- Run customer booking lookup smoke test.
- Run admin review/booking note/settlement smoke test.
- Record exact SQL files applied, operator, timestamp, and output summary.

## Explicitly forbidden

- Running `database/migrate.sh` end-to-end on production.
- Applying SQL without a DB backup.
- Applying SQL to a DB whose name has not been verified.
- Applying SQL to legacy KTaxi/TTaxi DBs.
- Copying staging data into production.
