# MVP Deployment Preparation

## Release Inputs

- Clean release branch and recorded previous HEAD
- Backend and frontend test results
- Explicit T-Ride DB name
- Schema preview for every required migration
- Verified DB backup and restore location
- Staging/production secrets supplied outside Git

## Database Policy

The migration runners replay all numbered SQL and do not maintain an applied-history table. Do not run the complete runner against an existing commercialization database.

For each release:

1. Confirm the target DB.
2. Create a consistent backup.
3. Inspect current enum, columns, tables, and affected rows.
4. Apply only missing migration files to the explicit DB.
5. Verify immediately and stop on mismatch.

`SETTLEMENT_PENDING` compatibility uses migrations 32 and 37. Staging received migration 37 selectively. Production requires a schema check before applying it.

## Selective Service Deployment

```bash
cd /opt/t-ride/deploy/docker
docker compose -f docker-compose.staging.yml up -d --build tride-backend
docker compose -f docker-compose.staging.yml up -d --build tride-frontend
```

Rebuild only services changed by the release. Documentation-only changes require no rebuild.

## Rollback

- Record `PREVIOUS_HEAD` before deployment.
- Switch T-Ride back to the previous release commit.
- Rebuild only affected `tride-*` services.
- Verify health and core APIs.
- Do not automatically reverse migrations or restore the whole DB during live operation.

Never change KTaxi, host 80/443, legacy nginx, legacy databases, or shared infrastructure.
