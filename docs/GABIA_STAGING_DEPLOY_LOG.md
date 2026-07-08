\# T-Ride Gabia Staging Deployment Log



\## 2026-07-07 Staging Docker Deployment Success



\### Server

\- Gabia VPS: 103.60.127.213

\- OS: Ubuntu 22.04.5 LTS

\- T-Ride path: `/opt/t-ride`

\- Docker compose: `/opt/t-ride/deploy/docker/docker-compose.staging.yml`

\- Compose project: `tride-staging`



\### Safety Rule

Existing KTaxi legacy stack must not be touched.



Do not modify or restart:

\- `/opt/ktaxi`

\- `ktaxi-\*` containers

\- `ktaxi-nginx`

\- `infra\_\*` volumes

\- `infra\_ktaxi-net`

\- host ports `80/443`



\### T-Ride Staging Containers

\- `tride-db`

\- `tride-backend`

\- `tride-frontend`



\### Staging Ports

\- Backend API: `103.60.127.213:3100`

\- Frontend: `103.60.127.213:3101`



\### Completed

\- T-Ride Docker staging stack deployed separately from legacy KTaxi.

\- DB changed to `mariadb:10.11`.

\- DB migration completed successfully.

\- Seed completed.

\- MVP E2E rehearsal completed.

\- `supertest` missing issue fixed by including dev dependencies in staging backend image.

\- Google Places backend proxy configured.

\- `/api/v1/places/autocomplete` returned `200 OK`.

\- Frontend opened normally on port `3101`.

\- Existing KTaxi legacy stack was not affected.



\### Confirmed Results



MVP E2E:



```text

All 19 checks passed.

Google Places autocomplete:

HTTP/1.1 200 OK
success: true
predictions returned
Important Environment Variables

The actual secret values must never be committed.

Required in server-only file:

/opt/t-ride/deploy/docker/.env

Google Places key:

GOOGLE_PLACES_API_KEY=<server-only-secret>

or compatible alias:

GOOGLE_MAPS_API_KEY=<server-only-secret>
Useful Check Commands
cd /opt/t-ride/deploy/docker

docker ps --format "table {{.Names}}\t{{.Ports}}\t{{.Status}}"

curl -i http://127.0.0.1:3100/api/v1/health
curl -I http://127.0.0.1:3101/
curl -i "http://127.0.0.1:3100/api/v1/places/autocomplete?input=pattaya&language=ko"
Current Good State

As of 2026-07-07:

T-Ride staging Docker deployment: OK
Backend health: OK
Frontend: OK
DB migration: OK
E2E rehearsal: 19/19 passed
Google Places autocomplete: OK
KTaxi legacy impact: none


## 2026-07-08 Staging Manual E2E Confirmed

### Confirmed from office PC
- Local `C:\TTaxi` synced with `origin/main`.
- Latest commit: `3cc740a fix(booking): correct airport dropoff pricing location payload`.
- T-Ride backend health: OK.
- T-Ride frontend: OK.
- Airport pickup BKK → Pattaya pricing: OK.
- Airport dropoff Pattaya → BKK pricing: OK.
- Browser manual flow: OK.
- Success tag created: `staging-manual-e2e-success-2026-07-08`.

### Access Rules
- `http://103.60.127.213` opens existing KTaxi. This is expected.
- T-Ride staging must be accessed with `http://103.60.127.213:3101/`.
- T-Ride backend API uses `http://103.60.127.213:3100/`.

### Safety
- Existing KTaxi legacy stack remained unaffected.
- Do not touch `/opt/ktaxi`, `ktaxi-*`, `ktaxi-nginx`, `80/443`, or legacy compose.

### Account recovery
- See [STAGING_ACCOUNT_RESET.md](./STAGING_ACCOUNT_RESET.md) for safe admin/driver password reset on T-Ride staging.

## 2026-07-08 Fare Table Image Seed (pending server apply)

### Local repo
- Migration: `database/28_fare_table_image_seed.sql` (idempotent upsert + soft-deactivate extras).
- Frontend inquiry UX: pricing `NOT_FOUND` → **문의** (`pricing_inquiry_required`).
- Tests: `backend/tests/fareTablePricing.test.js`, updated Flutter/backend suites.
- DB smoke: `database/smoke-test.ps1` fare-table assertions.
- Remote apply script: `deploy/scripts/apply-staging-fare-table.sh`.
- API smoke: `npm run smoke:staging:fare-table` (from backend).

### Apply on Gabia (T-Ride only)
```bash
cd /opt/t-ride
bash deploy/scripts/apply-staging-fare-table.sh
```

Or manually:
```bash
cd /opt/t-ride && git pull origin main
cd /opt/t-ride/deploy/docker
docker compose -f docker-compose.staging.yml up -d --build tride-backend tride-frontend
docker compose -f docker-compose.staging.yml exec tride-backend \
  sh -c 'cd /srv/tride/database && ./migrate.sh'
```

### Pre-apply staging API spot check (2026-07-08)
- BKK → Pattaya SUV: **1300** (partial/old seed)
- BKK → Bangkok Sedan, DMK → Pattaya VAN, Pattaya → DMK VAN: **NOT_FOUND** (migration 28 not applied yet)
- Bangkok → Hua Hin: **NOT_FOUND** (HUA_HIN location missing until migration 28)

### Post-apply verification
```bash
cd /opt/t-ride/backend
STAGING_BASE_URL=http://103.60.127.213:3100 npm run smoke:staging:fare-table
```

### Safety
- No KTaxi containers, volumes, or 80/443 touched.
- No `docker compose down`, no DB volume delete, no clean migration.
