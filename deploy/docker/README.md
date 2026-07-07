# T-Ride staging — Docker Compose

Isolated **T-Ride** stack for Gabia VPS staging. Runs beside legacy **KTaxi** at `/opt/ktaxi` without touching `ktaxi-*` containers, host **80/443**, or `ktaxi-postgres`.

| Item | Value |
|------|-------|
| Compose project | `tride-staging` |
| Compose file | `deploy/docker/docker-compose.staging.yml` |
| Server path | `/opt/t-ride` (clone repo; run compose from `deploy/docker/`) |
| Network | `tride-net` |
| DB | MariaDB 10.11 (`tride-db`), database `tride_staging` |
| Backend | `tride-backend` — container **3000**, host **3100** |
| Frontend | `tride-frontend` — nginx **80**, host **3101** |
| Volumes | `tride_mysql_data`, `tride_uploads`, `tride_logs` |

## Prerequisites

- Docker Engine + Docker Compose v2
- **Do not** install host nginx, PM2, or Node for this stack
- Legacy `ktaxi-nginx` continues to serve `88taxi.net` — **no changes in this step**

## Quick start (server)

```bash
cd /opt/t-ride/deploy/docker
cp .env.example .env
# Edit .env: replace SERVER_IP, passwords, JWT secrets (openssl rand -base64 48)

docker compose -f docker-compose.staging.yml up -d --build
docker compose -f docker-compose.staging.yml ps
```

### Smoke (split ports)

Replace `SERVER_IP` with the VPS public IP:

```bash
curl -s http://SERVER_IP:3100/api/v1/health
curl -s http://SERVER_IP:3100/api/v1/health/readiness
curl -s -o /dev/null -w "%{http_code}\n" http://SERVER_IP:3101/
curl -s -o /dev/null -w "%{http_code}\n" http://SERVER_IP:3101/booking/lookup
```

Browser:

- UI: `http://SERVER_IP:3101/`
- API (direct): `http://SERVER_IP:3100/api/v1/health`

**CORS:** frontend origin is `:3101`, API is `:3101` → `:3100`. Set in `.env`:

```env
CORS_ORIGIN=http://SERVER_IP:3101
PUBLIC_API_URL=http://SERVER_IP:3100
TRIDE_API_BASE_URL=http://SERVER_IP:3100
```

Rebuild frontend after changing `TRIDE_API_BASE_URL`:

```bash
docker compose -f docker-compose.staging.yml up -d --build tride-frontend
```

## Database image — MariaDB (not MySQL 8.4)

`tride-db` uses **`mariadb:10.11`** so the MariaDB **mysql client** inside `tride-backend` can authenticate without MySQL 8.4’s `caching_sha2_password` plugin (which Alpine/MariaDB clients do not load).

Env vars (`MYSQL_ROOT_PASSWORD`, `MYSQL_DATABASE`, `MYSQL_USER`, `MYSQL_PASSWORD`) and charset/timezone `command` flags are compatible with the official MariaDB image.

**Migrations:** `database/04_booking_core.sql` enforces one active assignment per booking via **`active_booking_id`** (STORED generated column + unique index). This replaces MySQL-only functional unique indexes so migrations succeed on MariaDB 10.11.

## Reset DB volume after image change (or failed first migration)

If `tride-db` previously ran as **`mysql:8.4`**, or migration failed partway, **delete only the T-Ride data volume** and recreate the stack **before** re-running `migrate.sh`:

```bash
cd /opt/t-ride/deploy/docker
docker compose -f docker-compose.staging.yml down

# T-Ride ONLY — never remove ktaxi / infra volumes
docker volume rm tride_mysql_data

docker compose -f docker-compose.staging.yml up -d --build
docker compose -f docker-compose.staging.yml ps
```

**Never delete:** `ktaxi_*`, `infra_*`, or any volume attached to `/opt/ktaxi` containers.

Verify T-Ride volumes only:

```bash
docker volume ls | grep tride
```

## Migration and seed

Wait until `tride-db` is healthy, then:

```bash
docker compose -f docker-compose.staging.yml exec tride-backend \
  sh -c 'cd /srv/tride/database && ./migrate.sh'
```

Compose injects `DB_*` and JWT vars from `deploy/docker/.env` into the container environment. `database/migrate.sh` passes **`--skip-ssl`** for MariaDB client compatibility inside the container.

Seed demo data (**tride_staging only**):

```bash
docker compose -f docker-compose.staging.yml exec tride-backend npm run seed:mvp-demo
docker compose -f docker-compose.staging.yml exec tride-backend npm run rehearsal:mvp-e2e
```

## Uploads on Gabia

Default: named volume `tride_uploads`. To use host path `/opt/t-ride/uploads`, add `docker-compose.override.yml`:

```yaml
services:
  tride-backend:
    volumes:
      - /opt/t-ride/uploads:/srv/tride/uploads
```

## Files

| File | Purpose |
|------|---------|
| `docker-compose.staging.yml` | `tride-db`, `tride-backend`, `tride-frontend` |
| `Dockerfile.backend` | Node 22 + MariaDB-compatible mysql client + migrate.sh |
| `Dockerfile.frontend` | Flutter web build + nginx |
| `nginx.frontend.conf` | SPA fallback + `/api/` proxy (future same-origin) |
| `.env.example` | Staging secrets template — copy to `.env` |

## Logs and teardown

```bash
docker compose -f docker-compose.staging.yml logs -f tride-backend
docker compose -f docker-compose.staging.yml down        # stops tride-* only
docker compose -f docker-compose.staging.yml down -v     # also removes volumes — destructive
```

## Static validation

- **Gabia server:** `docker compose -f docker-compose.staging.yml config` (requires populated `.env`)
- **Local dev machine:** Docker CLI may be unavailable — run `config` / `up` on the server

## Future step — public domain (not this phase)

`tride-staging.88taxi.net` will be added via **ktaxi-nginx** reverse proxy in a later phase. See [docs/GABIA_STAGING_DEPLOY_CHECKLIST.md](../../docs/GABIA_STAGING_DEPLOY_CHECKLIST.md) §7–8.

## Related docs

- [docs/GABIA_STAGING_DEPLOY_CHECKLIST.md](../../docs/GABIA_STAGING_DEPLOY_CHECKLIST.md)
- [docs/MVP_DEPLOYMENT_PREP.md](../../docs/MVP_DEPLOYMENT_PREP.md)
