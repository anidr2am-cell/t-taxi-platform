# T-Ride Backup and Restore Runbook

This runbook defines the minimum backup/restore process required before a
production deployment or migration.

## Backup policy

Suggested retention:

- Daily backups: 7 days
- Weekly backups: 4 weeks
- Monthly backups: 3 months

Backups must be copied off-server. A backup that exists only on the production
host is not enough.

## DB backup

Required properties:

- Full logical dump of the production T-Ride DB.
- Filename includes environment, DB name, Git HEAD, and UTC/Bangkok timestamp.
- Checksum generated after dump.
- Off-server copy completed.
- Backup success recorded in the deployment/incident log.

Example filename pattern:

```text
tride-production-DBNAME-HEAD-YYYYMMDD-HHMMSS.sql.gz
tride-production-DBNAME-HEAD-YYYYMMDD-HHMMSS.sql.gz.sha256
```

Example placeholder flow:

```bash
# Run only on the approved production host with approved secret handling.
# Do not paste real passwords into shared chat or committed files.

mysqldump \
  --single-transaction \
  --routines \
  --triggers \
  --events \
  --default-character-set=utf8mb4 \
  -h DB_HOST \
  -P DB_PORT \
  -u DB_USER \
  -p \
  DB_NAME | gzip > BACKUP_FILE.sql.gz

sha256sum BACKUP_FILE.sql.gz > BACKUP_FILE.sql.gz.sha256
```

## Upload/receipt backup

The upload volume contains customer/admin visible artifacts such as settlement
receipts. It must be backed up with a timestamp close to the DB backup.

Required properties:

- Backup the production upload volume, not staging.
- Filename includes environment, volume name, Git HEAD, and timestamp.
- Generate checksum or file-count manifest.
- Copy off-server.
- Record backup result.

Example filename pattern:

```text
tride-production-uploads-HEAD-YYYYMMDD-HHMMSS.tar.gz
tride-production-uploads-HEAD-YYYYMMDD-HHMMSS.tar.gz.sha256
```

## Restore rehearsal

Restore rehearsal must run in an isolated non-production environment.

Steps:

1. Create an isolated DB and upload storage target.
2. Restore the DB dump.
3. Restore the upload archive.
4. Start an isolated backend/frontend pointed only at the rehearsal DB.
5. Confirm backend health.
6. Confirm frontend loads.
7. Confirm booking lookup.
8. Confirm receipt download/access checks.
9. Confirm review query.
10. Confirm settlement query.
11. Record time-to-restore and problems found.

## Restore decision in production

Production restore is a high-risk incident action. It requires explicit approval
from the incident owner.

Restore may be considered when:

- Migration corrupts schema/data.
- Deployment writes invalid data that cannot be safely repaired.
- DB volume is lost or unusable.
- Upload volume is lost or corrupted.

Before restoring:

- Stop or isolate application writes.
- Record current broken state.
- Preserve logs.
- Confirm the selected backup checksum.
- Confirm the backup is from the correct production DB.
- Communicate downtime expectations.

After restoring:

- Run backend health check.
- Run frontend check.
- Run customer booking lookup.
- Run admin booking/review/settlement checks.
- Verify receipt access.
- Record final status and follow-up tasks.

## Backup monitoring

Before production traffic:

- Alert when DB backup fails.
- Alert when upload backup fails.
- Alert when backup file is missing or checksum generation fails.
- Alert when off-server copy fails.
- Alert when backup storage retention cleanup fails.
