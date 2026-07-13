# T-Ride

Thailand airport and city transfer platform.

Current commercialization RC flow:

`PENDING -> CONFIRMED -> DRIVER_ASSIGNED -> ON_ROUTE -> DRIVER_ARRIVED -> PICKED_UP -> SETTLEMENT_PENDING -> COMPLETED`

Drivers operate trips with in-app status buttons. Customer boarding/dropoff QR is not part of the current commercial UX. QR schema and APIs may remain for compatibility and must not be treated as the active workflow.

After trip end, the driver owes a fixed 200 THB commission. The booking remains `SETTLEMENT_PENDING` until the driver uploads a transfer slip and an administrator approves it. Approval changes the booking to `COMPLETED` and commission status to `PAID`.

Customer reviews are available in `SETTLEMENT_PENDING` and `COMPLETED`. Administrators can see rating, tags, comment, and timestamp. Drivers never receive raw comments, negative tags, admin issue reasons, or internal notes.

## Staging

- Repository path: `/opt/t-ride`
- Compose: `deploy/docker/docker-compose.staging.yml`
- Services: `tride-db`, `tride-backend`, `tride-frontend`
- API: `http://103.60.127.213:3100`
- UI: `http://103.60.127.213:3101`
- RC baseline: [docs/STAGING_COMMERCIALIZATION_RC.md](docs/STAGING_COMMERCIALIZATION_RC.md)

## Production readiness

Production is tracked separately from staging and is not approved until the
readiness checklist, deployment runbook, migration checklist, backup/restore
rehearsal, and admin recovery procedure are complete.

- Readiness: [docs/PRODUCTION_READINESS.md](docs/PRODUCTION_READINESS.md)
- Deployment runbook: [docs/PRODUCTION_DEPLOYMENT_RUNBOOK.md](docs/PRODUCTION_DEPLOYMENT_RUNBOOK.md)
- Migration checklist: [docs/PRODUCTION_MIGRATION_CHECKLIST.md](docs/PRODUCTION_MIGRATION_CHECKLIST.md)
- Backup/restore: [docs/BACKUP_RESTORE_RUNBOOK.md](docs/BACKUP_RESTORE_RUNBOOK.md)
- Admin recovery: [docs/ADMIN_ACCOUNT_RECOVERY.md](docs/ADMIN_ACCOUNT_RECOVERY.md)

## Safety

T-Ride is isolated from legacy KTaxi. Never modify `/opt/ktaxi`, `ktaxi-*`, `ktaxi-nginx`, host 80/443, `88taxi.net`, `infra_*`, or legacy databases.

Numbered migrations have no applied-history table and the runners replay all SQL files. Commercial deployment must back up the target DB, inspect its schema, and apply only required migrations to the explicitly selected database.

## Development

```powershell
cd C:\TTaxi\backend
npm test

cd C:\TTaxi\frontend
flutter test
```

See [docs/MVP_DEMO_GUIDE.md](docs/MVP_DEMO_GUIDE.md) for local setup and [docs/MVP_MANUAL_E2E_CHECKLIST.md](docs/MVP_MANUAL_E2E_CHECKLIST.md) for verification.
