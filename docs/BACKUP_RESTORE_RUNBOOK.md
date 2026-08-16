# T-Ride Backup and Restore Runbook

This runbook defines the minimum backup/restore process required before a
production deployment or migration.

## Backup policy

Suggested retention:

- Daily backups: 14 days
- Weekly backups: 8 weeks
- Monthly backups: 6 months

Backups must be copied off-server. A backup that exists only on the production
host is not enough.

## DB backup

Required properties:

- Full logical dump of the production T-Ride DB.
- Filename includes environment, DB name, Git HEAD, and UTC/Bangkok timestamp.
- Checksum generated after dump.
- Off-server copy completed.
- Backup success recorded in the deployment/incident log.

### Staging automated runners (T-Ride only)

These scripts are scoped to `/opt/t-ride`, `tride-db`, and `tride_staging` only.
They never touch `/opt/ktaxi`, `ktaxi-*`, or legacy volumes.

**Backup:**

```bash
bash /opt/t-ride/backend/scripts/run-staging-db-backup.sh
```

Expected safe output includes:

```text
BACKUP_FILE=/opt/t-ride/backups/tride_staging-YYYYMMDD-HHMMSS.sql.gz
BACKUP_SIZE_BYTES=...
BACKUP_SHA256=...
GZIP_TEST=PASS
BACKUP_RESULT=PASS
MANIFEST_FILE=/opt/t-ride/backups/tride_staging-YYYYMMDD-HHMMSS.manifest
```

Each backup writes a companion manifest with snapshot table counts, migration
file ceiling from the repo, and critical constraint presence checks. Manifests
contain no passwords, tokens, or customer PII.

**Restore rehearsal (isolated disposable MariaDB 10.11 container):**

```bash
bash /opt/t-ride/backend/scripts/run-staging-db-restore-rehearsal.sh \
  /opt/t-ride/backups/tride_staging-YYYYMMDD-HHMMSS.sql.gz
```

Warning:

```text
NEVER restore a rehearsal backup into tride_staging or tride-db.
```

The rehearsal runner:

- uses container `tride-restore-rehearsal`
- uses database `tride_restore_rehearsal`
- stores data in tmpfs only
- does not mount `tride_mysql_data`
- does not publish a host port
- removes the disposable container in an EXIT trap

**Health check after live rehearsal (manual):**

```bash
curl -fsS http://172.18.0.1:3100/api/v1/health
curl -fsS https://trider.taxi/api/v1/health
```

**Retention helper (dry-run by default; cron not installed automatically):**

```bash
bash /opt/t-ride/backend/scripts/prune-staging-db-backups.sh
bash /opt/t-ride/backend/scripts/prune-staging-db-backups.sh --apply
```

Recommended policy before enabling automation:

- daily backups
- keep 14 daily copies
- keep 8 weekly copies
- keep 6 monthly copies
- copy off-server

### Daily backup cycle (manual until systemd is enabled)

```bash
bash /opt/t-ride/backend/scripts/run-staging-db-backup-cycle.sh
```

Cycle flow:

1. acquire `/opt/t-ride/logs/backups/backup-cycle.lock`
2. run local backup + manifest verification
3. copy backup + manifest off-server when remote is enabled
4. verify remote upload
5. run local retention only when **all** gates pass and `TRIDE_BACKUP_AUTO_PRUNE=1`

Safe output fields:

```text
BACKUP_RESULT=PASS|FAIL
REMOTE_COPY_RESULT=PASS|FAIL|SKIPPED_DISABLED
REMOTE_VERIFY_RESULT=PASS|FAIL|SKIPPED_DISABLED
LOCAL_PRUNE_RUN=YES|NO
```

While remote is disabled (`TRIDE_BACKUP_REMOTE_ENABLED=0`):

```text
REMOTE_COPY_RESULT=SKIPPED_DISABLED
LOCAL_PRUNE_RUN=NO
```

Local pruning is **never** allowed when remote copy is disabled or failed.

### Off-server copy configuration (example only)

Copy the example file on the server:

```bash
cp /opt/t-ride/deploy/env.backup.example /opt/t-ride/.env.backup
```

Configure rclone on the host separately. The repository stores only:

```text
TRIDE_BACKUP_REMOTE_ENABLED=0
TRIDE_BACKUP_REMOTE_NAME=
TRIDE_BACKUP_REMOTE_PATH=T-Rider
TRIDE_BACKUP_AUTO_PRUNE=0
```

Never commit access keys, secret keys, tokens, or DB passwords.

Manual remote copy test:

```bash
bash /opt/t-ride/backend/scripts/staging-db-backup-remote.sh \
  /opt/t-ride/backups/tride_staging-YYYYMMDD-HHMMSS.sql.gz \
  /opt/t-ride/backups/tride_staging-YYYYMMDD-HHMMSS.manifest
```

Remote path layout:

```text
<TRIDE_BACKUP_REMOTE_PATH>/staging/db/YYYY/MM/<filename>
```

Remote retention mutation is **not** implemented in this step. Keep off-server
copies equal to or longer than local retention.

### Monthly restore rehearsal wrapper

```bash
bash /opt/t-ride/backend/scripts/run-staging-db-monthly-rehearsal.sh
```

This selects the newest complete local backup+manifest pair, runs the isolated
restore rehearsal runner, then checks:

```bash
curl -fsS http://172.18.0.1:3100/api/v1/health
curl -fsS https://trider.taxi/api/v1/health
```

Warning:

```text
NEVER automatically restore into tride_staging or tride-db.
Actual staging/production restore remains a separate manual incident procedure.
```

### Systemd templates (create only — do not enable yet)

Version-controlled unit files:

```text
deploy/systemd/tride-staging-db-backup.service
deploy/systemd/tride-staging-db-backup.timer
deploy/systemd/tride-staging-db-rehearsal.service
deploy/systemd/tride-staging-db-rehearsal.timer
```

Suggested schedules:

- daily backup: `02:30` with `Timezone=Asia/Bangkok`
- monthly rehearsal: first Sunday `04:00` with `Timezone=Asia/Bangkok`

Install later (operator action only):

```bash
sudo cp /opt/t-ride/deploy/systemd/tride-staging-db-backup.* /etc/systemd/system/
sudo cp /opt/t-ride/deploy/systemd/tride-staging-db-rehearsal.* /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now tride-staging-db-backup.timer
sudo systemctl enable --now tride-staging-db-rehearsal.timer
```

Check status:

```bash
systemctl status tride-staging-db-backup.timer
systemctl status tride-staging-db-rehearsal.timer
journalctl -u tride-staging-db-backup.service
journalctl -u tride-staging-db-rehearsal.service
```

Disable later:

```bash
sudo systemctl disable --now tride-staging-db-backup.timer
sudo systemctl disable --now tride-staging-db-rehearsal.timer
```

### Structured logs

Backup cycle and monthly rehearsal logs:

```text
/opt/t-ride/logs/backups/
```

Logs include timestamps, filenames, sizes, hashes, remote results, and prune
results. They never include DB credentials or remote secrets.

### Alert hook

Disabled by default. Enable with:

```text
TRIDE_BACKUP_ALERT_ENABLED=1
TRIDE_BACKUP_ALERT_SCRIPT=/opt/t-ride/backend/scripts/staging-db-backup-alert.sh
```

Current alert delivery is log-only until a real notification provider is wired.

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
