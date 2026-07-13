# T-Ride Production Readiness

Status: IN PROGRESS

This document tracks the production readiness work after the first audit. It is
not a deployment approval. A production release is allowed only after every P0
item is DONE and the owner explicitly approves the deployment window.

## Current baseline

- Base branch/HEAD: `main` at `c236926520128f74c7354fd43acd2f85c41d2381`
- Work branch: `chore/production-readiness`
- First audit decision: NOT READY
- This step creates production templates and runbooks only.
- No production deploy, staging deploy, migration, rebuild, nginx change, or
  secret entry has been performed.

## P0 readiness checklist

| Item | Status | Notes |
|---|---|---|
| Production compose draft | IN PROGRESS | `deploy/docker/docker-compose.production.yml` exists as a draft and still needs server review. |
| Production env template | IN PROGRESS | `deploy/docker/.env.production.example` contains placeholders only. |
| Production DB separation | TODO | Confirm a T-Ride-only production DB name, user, host, grants, and backup target. Never use legacy `ttaxi`, KTaxi, or staging DBs. |
| Domain/TLS topology | TODO | Recommended topology is same-origin `https://tride.example.com` with `/api` and `/socket.io` routing. Actual domain/cert/proxy not configured here. |
| Backup/restore plan | IN PROGRESS | See `docs/BACKUP_RESTORE_RUNBOOK.md`; rehearsal still required. |
| Migration preview | IN PROGRESS | See `docs/PRODUCTION_MIGRATION_CHECKLIST.md`; no SQL was executed. |
| Admin account recovery | IN PROGRESS | See `docs/ADMIN_ACCOUNT_RECOVERY.md`; production credential handling still required. |
| Monitoring and alerting | TODO | Health, 5xx, disk, upload volume, DB backup, container restart, and TLS expiry alerts must be configured. |
| Rollback runbook | IN PROGRESS | Included in `docs/PRODUCTION_DEPLOYMENT_RUNBOOK.md`; must be rehearsed. |

## P1 readiness checklist

| Item | Status | Notes |
|---|---|---|
| Log rotation | IN PROGRESS | Production compose draft sets Docker json-file rotation. App log rotation is still TODO. |
| Disk alert | TODO | Alert for DB volume, upload volume, logs, and host disk usage. |
| 5xx alert | TODO | Add API error-rate monitoring before production traffic. |
| Upload volume alert | TODO | Alert on free space and backup failure. |
| Dependency moderate vulnerabilities | TODO | `npm audit --omit=dev` reported moderate dependency issues in the Firebase/Google stack. Track upgrade separately. |
| Staging/test data removal | TODO | Confirm no demo accounts, demo bookings, test reservations, or rehearsal data are present in production DB. |
| Production seed blocked | TODO | Verify `NODE_ENV=production` and never run demo seed scripts against production. |
| Frontend URL fail-fast | TODO | Runtime code still has localhost defaults if build args are omitted. Production build procedure must enforce API/SOCKET URLs. |
| Production runtime image hardening | TODO | Current backend Dockerfile is staging-oriented and includes devDependencies. A production runtime image/target should be created before final launch. |

## Fail-fast audit

| Area | Current behavior | Risk | Next action |
|---|---|---|---|
| Backend JWT secrets | Production-like environments reject weak `JWT_ACCESS_SECRET` and `JWT_REFRESH_SECRET`. | Good guard, but placeholder secrets in env files must never reach server. | Verify real values only in server secret store. |
| Backend DB password | Production-like environments reject empty `DB_PASSWORD`. | Good guard. | Confirm production-only DB user and grants. |
| CORS | Production-like environments reject missing or wildcard `CORS_ORIGIN`. | Good guard. | Use exact HTTPS origin. |
| QR dev reissue | Production-like environments reject `ALLOW_DEV_QR_REISSUE=true`. | Good guard. | Keep false. |
| Frontend API URL | Flutter config defaults to localhost if `API_BASE_URL` is omitted. | Dangerous production fallback. | Enforce build args in compose/runbook; later add code/build fail-fast. |
| Frontend Dockerfile | Default build arg is localhost. | Dangerous if used directly outside compose. | Later remove localhost default or add production build target. |
| Upload root | Backend defaults to local `./uploads` if unset. | In container it is overridden, but direct production process could use temporary path. | Require `UPLOAD_DIR` in production runbook. |

## Recommended production topology

Initial recommendation: same-origin.

```text
https://tride.example.com/
  /                  -> tride-prod-frontend
  /api               -> tride-prod-backend:3000
  /socket.io         -> tride-prod-backend:3000
```

Requirements:

- HTTPS termination with a valid certificate.
- HTTP to HTTPS redirect.
- HSTS after the domain is confirmed stable.
- WebSocket upgrade for Socket.IO.
- Upload body size equal to or greater than backend upload limit.
- `X-Forwarded-*` headers preserved.
- No direct changes to legacy KTaxi nginx, host 80/443, or `88taxi.net` without a separate reviewed cutover plan.

## Current decision

Production is still NOT READY. The new files reduce planning risk but do not
replace production infrastructure review, backup rehearsal, migration rehearsal,
or final security review.
