# T-Ride Production Deployment Runbook

This runbook is a controlled checklist for a future production deployment. It is
not permission to deploy. Replace placeholders only on the production server or
approved secret store.

## Hard prohibitions

Do not:

- Run `docker compose down`.
- Run `docker system prune`, `docker volume prune`, or network prune commands.
- Run the full `database/migrate.sh` against an existing production DB.
- Restart, edit, or depend on legacy `/opt/ktaxi`, `ktaxi-*`, `ktaxi-nginx`,
  legacy nginx, host 80/443, `88taxi.net`, `infra_*` volumes, or legacy DBs.
- Copy staging DB data into production.
- Run demo seed scripts against production.
- Commit production secrets.

## 1. Pre-deployment confirmation

Record before starting:

- Deployment owner:
- Deployment window:
- Expected production branch/tag:
- Current Git HEAD:
- `PREVIOUS_HEAD`:
- Production compose file:
- Production env file path:
- Target DB name:
- Backup location:
- Rollback owner:

Required checks:

```bash
git status --short
git branch --show-current
git rev-parse HEAD
git log --oneline --decorate -5
```

Proceed only when the working tree is clean and the approved branch/tag matches
the deployment request.

## 2. Environment check

Confirm the production `.env.production` exists on the server and is readable
only by the deployment user.

Required values:

- `NODE_ENV=production`
- production-only `DB_NAME`, `DB_USER`, `DB_PASSWORD`
- strong `MYSQL_ROOT_PASSWORD`
- strong `JWT_ACCESS_SECRET`, `JWT_REFRESH_SECRET`
- exact HTTPS `CORS_ORIGIN` / `ALLOWED_ORIGINS`
- exact HTTPS `PUBLIC_API_URL` / `BACKEND_PUBLIC_URL`
- `APP_ENV=production`
- exact HTTPS `API_BASE_URL` and `SOCKET_URL`, or same-origin `/api` for
  `API_BASE_URL`
- `SWAGGER_ENABLED=false`
- `ALLOW_DEV_QR_REISSUE=false`
- persistent `UPLOAD_DIR`
- persistent `LOG_DIR`

Do not print secrets to terminal history, chat, issue comments, or logs.

## 3. Backup before change

Before any deploy or migration:

1. Create a DB full dump.
2. Create a checksum for the dump.
3. Copy the dump off-server.
4. Back up the upload/receipt volume at a matching time.
5. Record backup filenames and checksums in the incident/deployment log.

Use `docs/BACKUP_RESTORE_RUNBOOK.md`.

## 4. Schema pre-check

Before migration, confirm:

- The target DB is the production T-Ride DB, not legacy or staging.
- The current schema is compatible with the expected migration.
- Required tables exist.
- Existing enum values match expectations.
- No unexpected schema drift exists.

Use `docs/PRODUCTION_MIGRATION_CHECKLIST.md`.

## 5. Selective migration

Apply only reviewed missing migration files in this order:

1. `database/35_review_tags.sql`
2. `database/36_admin_booking_notes.sql`
3. `database/37_add_settlement_pending_booking_status.sql`

Do not run the full migration runner. Record the exact SQL file, DB name,
operator, timestamp, and post-check result.

## 6. Build/deploy sequence

The production compose draft uses separate production service names:

- `tride-prod-db`
- `tride-prod-backend`
- `tride-prod-frontend`

Before first launch, run a compose config render in a safe review session:

```bash
docker compose \
  --env-file deploy/docker/.env.production \
  -f deploy/docker/docker-compose.production.yml \
  config
```

Review the output for:

- no real secret exposure in shared channels
- no staging names
- no legacy names
- no host 80/443 binds
- no DB host port publication
- correct local backend/frontend ports
- correct production URL build args
- `APP_ENV=production` passed to the frontend build
- backend build uses `target: production`
- backend runtime runs as the non-root `node` user
- backend production image does not include backend tests, full `database/`, or
  devDependencies
- backend upload/log mounts match `UPLOAD_DIR=/srv/tride/uploads` and
  `LOG_DIR=/srv/tride/logs`

The frontend production build must fail when:

- `APP_ENV` is missing.
- `API_BASE_URL` is missing.
- `SOCKET_URL` is missing.
- `API_BASE_URL` or `SOCKET_URL` points to `localhost` or `127.0.0.1`.
- `API_BASE_URL` is not `/api` or an absolute HTTPS URL.
- `SOCKET_URL` is not an absolute HTTPS URL.

The Dockerfile intentionally has no localhost default in the `API_BASE_URL` or
`SOCKET_URL` build arg declarations. Localhost fallback is allowed only inside
the non-production build path.

Then deploy only during the approved window. Prefer rebuilding only changed
services. Do not use stack-wide teardown.

Production compose commands must pass the production env file explicitly:

```bash
docker compose \
  --env-file deploy/docker/.env.production \
  -f deploy/docker/docker-compose.production.yml \
  config
```

### Backend upload/log volume permissions

The production backend image creates `/srv/tride/uploads` and
`/srv/tride/logs` as `node:node` before switching to `USER node`. New production
named volumes are initialized from those prepared directories. If an existing
volume is reused, or if an external bind mount is used instead of the named
volumes, verify the UID/GID and write permissions before deployment.

## 7. Health checks

After deploy:

- Check container health.
- Check backend health endpoint.
- Check frontend HTTP response.
- Check `/api` reverse proxy route.
- Check `/socket.io` WebSocket upgrade.
- Check logs for startup errors without exposing secrets.

## 8. Smoke tests

Perform minimal production smoke tests with non-demo data:

### Customer

- Open frontend over HTTPS.
- Create or look up a controlled booking.
- Confirm booking status and price display.
- Confirm customer support/chat entry points.

### Driver

- Login with an approved driver account.
- Confirm assigned booking visibility.
- Confirm trip status buttons are visible and safe.

### Admin

- Login with an approved admin account.
- Confirm booking management loads.
- Confirm reviews, settlements, and admin notes screens load.
- Confirm no staging/test labels or demo data appear.

## 9. Monitoring confirmation

Before opening traffic:

- Container restart alert enabled.
- Backend 5xx alert enabled.
- Host disk alert enabled.
- DB volume alert enabled.
- Upload volume alert enabled.
- Backup success/failure alert enabled.
- TLS expiry alert enabled.

## 10. Rollback conditions

Rollback if any of these occur:

- Backend health fails repeatedly.
- Frontend cannot load over HTTPS.
- Login or booking lookup fails for normal users.
- Migration post-check fails.
- Error rate exceeds the approved threshold.
- Receipt upload/download is broken.
- Production DB identity is uncertain.

Rollback method:

1. Stop traffic through the production proxy, if possible.
2. Revert to `PREVIOUS_HEAD` or previous image/version.
3. Restore frontend/backend service versions.
4. Restore DB only if a migration caused irreversible data/schema failure and
   the rollback owner approves.
5. Keep all logs and deployment notes for incident review.

## 11. Incident record

Record:

- Timeline.
- Commands executed.
- Git HEAD before/after.
- Migration files applied.
- Backup filenames/checksums.
- Smoke test results.
- Problems found.
- Rollback actions, if any.
- Follow-up tasks.
