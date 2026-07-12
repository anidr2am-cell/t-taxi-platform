# Gabia T-Ride Staging Checklist

## Scope

- Path: `/opt/t-ride`
- Compose: `/opt/t-ride/deploy/docker/docker-compose.staging.yml`
- DB: `tride_staging` in `tride-db`
- API: 3100
- Frontend: 3101

## Preflight

- [ ] Git tree clean; branch and HEAD recorded
- [ ] `docker compose ... ps` shows only expected T-Ride services
- [ ] `MYSQL_DATABASE=tride_staging`
- [ ] Backend and frontend health successful
- [ ] Required schema/data preview complete
- [ ] T-Ride DB backup is non-empty

## Migration

- [ ] Do not run the full numbered migration runner
- [ ] Apply only missing SQL to explicit `tride_staging`
- [ ] Remove or safely replace legacy `USE ttaxi` only in a temporary copy
- [ ] Validate every migration before proceeding
- [ ] Migration 37 is the staging enum compatibility migration
- [ ] There is no settlement-pending migration numbered 31

## Deploy

```bash
cd /opt/t-ride
git fetch origin <release-branch>
git switch -C <release-branch> origin/<release-branch>

cd deploy/docker
docker compose -f docker-compose.staging.yml up -d --build tride-backend
curl -fsS http://127.0.0.1:3100/api/v1/health
docker compose -f docker-compose.staging.yml up -d --build tride-frontend
curl -fsSI http://127.0.0.1:3101/ | head -n 1
```

Documentation-only commits do not require rebuild or migration.

## Legacy Guard

Never access or modify `/opt/ktaxi`, `ktaxi-*`, `ktaxi-nginx`, host 80/443, `88taxi.net`, certbot, `infra_*`, legacy DB, or `ttaxi`. Never use stack teardown, prune, or legacy restart commands.
