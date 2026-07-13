# T-Ride Docker

Isolated staging stack beside legacy KTaxi.

| Item | Value |
|---|---|
| Server path | `/opt/t-ride` |
| Compose | `deploy/docker/docker-compose.staging.yml` |
| DB | `tride-db`, MariaDB 10.11, `tride_staging` |
| Backend | `tride-backend`, host 3100 -> container 3000 |
| Frontend | `tride-frontend`, host 3101 -> container 80 |
| Volumes | `tride_mysql_data`, `tride_uploads`, `tride_logs` |

The backend image contains the database directory at `/srv/tride/database`. This does not authorize running the full migration runner.

## Production Draft

Production planning files are separate from staging:

| Item | Value |
|---|---|
| Compose draft | `deploy/docker/docker-compose.production.yml` |
| Env template | `deploy/docker/.env.production.example` |
| Project name | `tride-production` |
| Services | `tride-prod-db`, `tride-prod-backend`, `tride-prod-frontend` |
| Network | `tride-prod-net` |
| Volumes | `tride_prod_mysql_data`, `tride_prod_uploads`, `tride_prod_logs` |

The production draft does not bind host 80/443 and does not expose the DB port.
TLS and reverse proxy routing require a separate reviewed production change.
The production backend uses the `production` target from
`deploy/docker/Dockerfile.backend`; staging keeps the default `staging` target
with devDependencies for smoke/rehearsal tooling.
Production upload/log named volumes mount to `/srv/tride/uploads` and
`/srv/tride/logs`, which the production image prepares as `node:node`. Check
ownership first when reusing an existing volume or using a bind mount.
Read these documents before any production work:

- `docs/PRODUCTION_READINESS.md`
- `docs/PRODUCTION_DEPLOYMENT_RUNBOOK.md`
- `docs/PRODUCTION_MIGRATION_CHECKLIST.md`
- `docs/BACKUP_RESTORE_RUNBOOK.md`
- `docs/ADMIN_ACCOUNT_RECOVERY.md`

## Selective Deployment

Check Git and containers first:

```bash
cd /opt/t-ride
git status --short
git branch --show-current
git rev-parse HEAD

cd deploy/docker
docker compose -f docker-compose.staging.yml ps
```

Rebuild only a changed service:

```bash
docker compose -f docker-compose.staging.yml up -d --build tride-backend
docker compose -f docker-compose.staging.yml up -d --build tride-frontend
```

Health checks:

```bash
curl -fsS http://127.0.0.1:3100/api/v1/health
curl -fsSI http://127.0.0.1:3101/ | head -n 1
```

## Migration Policy

`database/migrate.sh` and `migrate.ps1` replay all numbered files and do not maintain `schema_migrations`. For commercialization:

1. Confirm `MYSQL_DATABASE=tride_staging`.
2. Back up T-Ride DB.
3. Inspect current schema.
4. Apply only missing SQL files against the explicit target DB.
5. Verify schema and affected data after every file.

Do not run the full migration runner for an existing commercial database.

## Legacy Protection

Never access or change `/opt/ktaxi`, `ktaxi-*`, `ktaxi-nginx`, host 80/443, `88taxi.net`, certbot, `infra_*`, or legacy databases. Do not use stack-wide teardown, system prune, volume prune, or network prune commands.
