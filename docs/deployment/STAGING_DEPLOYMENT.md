# TTaxi Staging Deployment

This pack prepares the repository for staging. It does not deploy to any remote server.

## Architecture

```text
Browser / Flutter Web
  -> Nginx HTTPS
      -> static Flutter files
      -> /api/ proxy to Node.js backend
      -> /socket.io/ proxy to Socket.IO
Node.js backend (PM2, one instance)
  -> MySQL 8
  -> local persistent upload directory
  -> optional SMTP, Firebase Admin, Google Places, Aviationstack
```

Use one backend instance for staging. The automatic flight sync worker uses a single-process in-memory lock; multi-instance deployment needs a distributed lock or queue first.

## Prerequisites

- Linux server with Node.js 22+, npm, Flutter SDK for build host, MySQL 8, Nginx, and PM2.
- PowerShell Core or MySQL CLI access for the current migration runner.
- A real domain and HTTPS certificate chosen by the operator.
- No real credentials committed to Git.

## Directory Layout

```text
/srv/ttaxi/releases/<release-id>/
/srv/ttaxi/current -> /srv/ttaxi/releases/<release-id>
/var/lib/ttaxi/uploads
/var/log/ttaxi
```

Create upload/log directories before starting the API:

```bash
sudo mkdir -p /var/lib/ttaxi/uploads /var/log/ttaxi
sudo chown -R <app-user>:<app-user> /var/lib/ttaxi /var/log/ttaxi
```

## Environment Setup

Copy `backend/.env.example` to `backend/.env` on the server and replace placeholders. Required staging values:

- `NODE_ENV=production` or `NODE_ENV=staging`
- `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`
- `JWT_ACCESS_SECRET`, `JWT_REFRESH_SECRET`
- `CORS_ORIGIN=https://<staging-domain>`
- `PUBLIC_API_URL=https://<staging-domain>`
- `UPLOAD_DIR=/var/lib/ttaxi/uploads`

Optional integrations may be blank:

- `GOOGLE_MAPS_API_KEY`
- `SMTP_*`
- `FIREBASE_*`
- `AVIATIONSTACK_*`

Staging-sensitive defaults:

- `ALLOW_DEV_QR_REISSUE=false`
- `FLIGHT_SYNC_ENABLED=false` until a provider key and one-instance process model are confirmed.
- `SWAGGER_ENABLED=false` unless the staging API docs are intentionally exposed.

## Database Preparation

Create a database and limited user. Use placeholders here; do not paste real passwords into scripts.

```sql
CREATE DATABASE ttaxi_staging CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'ttaxi_app'@'%' IDENTIFIED BY '<strong-password>';
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, ALTER, INDEX, REFERENCES, CREATE VIEW, SHOW VIEW
  ON ttaxi_staging.* TO 'ttaxi_app'@'%';
FLUSH PRIVILEGES;
```

Back up before every migration:

```bash
mysqldump --single-transaction --routines --triggers \
  -h <db-host> -P <db-port> -u <backup-user> -p ttaxi_staging \
  > ttaxi_staging_$(date +%Y%m%d_%H%M%S).sql
```

## Migrations

Current runner: `database/migrate.ps1`. It reads `backend/.env`, sorts numbered SQL files lexicographically by full filename, and runs them in deterministic order.

Validate order:

```bash
cd /srv/ttaxi/current/backend
npm run validate:migrations
```

Current duplicate numeric prefix:

- `21_flight_monitor.sql`
- `21_notification_device_registration.sql`

This is accepted because execution order is lexicographic by full filename. Do not rename already-applied migrations.

Audit notes:

- Numbered migrations use `CREATE TABLE IF NOT EXISTS`, guarded procedures, information schema checks, or duplicate-safe seed statements where reruns are expected.
- `15_pricing_architecture.sql` contains guarded legacy table/column drops for the historical pricing migration. Do not run it against an unrelated database.
- `schema.sql` is a legacy/reference schema file and is not selected by `migrate.ps1` because it is not a numbered migration filename.

Run migrations from the repository root:

```bash
pwsh ./database/migrate.ps1 -EnvFile ./backend/.env
pwsh ./database/migrate.ps1 -EnvFile ./backend/.env
```

The second run verifies idempotency. The migration runner should stop on the first real SQL error and print the failing filename without printing credentials.

Critical tables to verify:

```sql
SHOW TABLES LIKE 'bookings';
SHOW TABLES LIKE 'booking_transfer_details';
SHOW TABLES LIKE 'driver_assignments';
SHOW TABLES LIKE 'commission_obligations';
SHOW TABLES LIKE 'notification_deliveries';
SHOW TABLES LIKE 'driver_locations';
```

Rollback limitation: migrations are forward-only. Restore the latest DB backup for schema/data rollback.

## Backend Install and Start

```bash
cd /srv/ttaxi/current/backend
npm ci --omit=dev
node -e "require('./src/config/env'); console.log('env ok')"
pm2 start ../../deploy/pm2/ecosystem.config.cjs
pm2 save
pm2 logs ttaxi-api-staging
```

The PM2 template uses one forked instance. Do not scale it while the flight sync worker uses in-memory locking.

Health checks:

```bash
curl -fsS https://<staging-domain>/api/v1/health
curl -fsS https://<staging-domain>/api/v1/health/readiness
```

Readiness fails only required dependencies: database and upload directory writability. SMTP, Firebase, and Aviationstack are reported as booleans but do not fail readiness.

## Flutter Web Build

Build with staging URLs. Do not leave localhost in a staging build.

```bash
cd /srv/ttaxi/current/frontend
flutter pub get
flutter build web --release \
  --dart-define=API_BASE_URL=https://<staging-domain> \
  --dart-define=SOCKET_URL=https://<staging-domain> \
  --dart-define=FIREBASE_API_KEY=<public-web-api-key-if-used> \
  --dart-define=FIREBASE_APP_ID=<public-web-app-id-if-used> \
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=<public-sender-id-if-used> \
  --dart-define=FIREBASE_PROJECT_ID=<public-project-id-if-used> \
  --dart-define=FIREBASE_AUTH_DOMAIN=<public-auth-domain-if-used> \
  --dart-define=FIREBASE_STORAGE_BUCKET=<public-storage-bucket-if-used> \
  --dart-define=FIREBASE_VAPID_KEY=<public-vapid-key-if-used>
```

Firebase web config values are public identifiers, not backend service account credentials. Never put Firebase Admin private keys in Flutter.

The app uses hash/direct routes; Nginx must fall back to `index.html`. Do not aggressively cache `index.html`; hashed Flutter assets may be cached immutably.

## Nginx

Use `deploy/nginx/ttaxi-staging.conf` as a template. Replace:

- `staging.example.com`
- certificate paths
- `root`
- backend upstream port if different

Validate and reload:

```bash
sudo nginx -t
sudo systemctl reload nginx
```

The template proxies:

- `/api/` to backend
- `/socket.io/` with WebSocket upgrade headers
- Flutter static files with `index.html` fallback

It forwards `Authorization` and `X-Guest-Access-Token` and sets `client_max_body_size 10m`, matching the default upload limit.

## Upload Storage

Current MVP stores receipts on local disk via `UPLOAD_DIR`, grouped by date. Requirements:

- Use a persistent directory outside release/build folders, e.g. `/var/lib/ttaxi/uploads`.
- Ensure the API user can create/write/delete probe files.
- Back up this directory with database backups.
- Do not expose it directly from Nginx. Receipt downloads must stay behind authorized API endpoints.
- Current allowed MIME families: `image/*` and `application/pdf`.
- Current max size: `UPLOAD_MAX_FILE_SIZE_MB`, default `10`.

## CORS and Socket.IO

Set `CORS_ORIGIN` to exact origins, comma-separated if needed:

```env
# Local development example:
CORS_ORIGIN=http://localhost:58001,http://localhost:8080

# Staging example:
CORS_ORIGIN=https://<staging-domain>
```

Do not use wildcard origins with credentials. Required headers include:

- `Authorization`
- `X-Guest-Access-Token`
- `Content-Type`

Socket.IO uses `SOCKET_PATH=/socket.io` and the same frontend origin.

## Flight Sync Worker

Staging default:

```env
FLIGHT_SYNC_ENABLED=false
```

When enabling:

- Confirm `AVIATIONSTACK_API_KEY` is configured.
- Run only one backend instance.
- Verify `GET /api/v1/admin/flights/sync-status`.
- Use `POST /api/v1/admin/flights/run-sync-cycle` for controlled admin testing.

Disable quickly by setting `FLIGHT_SYNC_ENABLED=false` and restarting PM2.

## Smoke Test

Read-only smoke test:

```bash
cd /srv/ttaxi/current/backend
STAGING_BASE_URL=https://<staging-domain> \
STAGING_FRONTEND_URL=https://<staging-domain> \
npm run smoke:staging
```

Checks:

- frontend root
- admin and driver route fallback
- health
- readiness
- unauthorized admin boundary
- Socket.IO polling handshake

It does not create bookings or modify staging data.

## Security Checklist

- Strong, unique JWT secrets.
- `DB_PASSWORD` set and not reused.
- `ALLOW_DEV_QR_REISSUE=false`.
- Test admin/driver accounts removed, disabled, or clearly limited.
- Seed scripts are not run automatically.
- Swagger disabled unless intentionally exposed.
- CORS origins exact; no wildcard with credentials.
- Upload MIME and size limits verified.
- Receipt files not publicly served.
- Logs do not include tokens, passwords, API keys, SMTP credentials, Firebase private keys, or raw provider payloads.
- Admin endpoints require ADMIN/SUPER_ADMIN.
- Guest access token headers are allowed but not logged.
- SQL remains parameterized through repositories.

## Backup and Rollback

Before release:

- DB dump with `mysqldump`.
- Copy `/var/lib/ttaxi/uploads`.
- Keep previous `/srv/ttaxi/releases/<release-id>`.

Rollback app:

```bash
ln -sfn /srv/ttaxi/releases/<previous-release-id> /srv/ttaxi/current
cd /srv/ttaxi/current/backend
npm ci --omit=dev
pm2 restart ttaxi-api-staging
sudo systemctl reload nginx
```

Rollback DB:

- Restore the pre-migration dump.
- Restore matching upload directory snapshot if receipt data changed.

Disable optional integrations without stopping bookings:

- SMTP: clear `SMTP_HOST`.
- Firebase: clear `FIREBASE_PROJECT_ID` or service account settings.
- Flight provider: clear `AVIATIONSTACK_API_KEY`.
- Flight worker: set `FLIGHT_SYNC_ENABLED=false`.

## Troubleshooting

- `readiness` degraded with database disconnected: check DB host, port, user grants, firewall, and `DB_NAME`.
- `readiness` degraded with upload not writable: check `UPLOAD_DIR` existence, owner, and permissions.
- Browser CORS error: confirm exact `CORS_ORIGIN` and Nginx HTTPS origin.
- Socket connection fails: confirm `/socket.io/` Nginx location and WebSocket headers.
- Flight sync status provider false: configure Aviationstack or keep worker disabled.
- Flutter route refresh 404: check Nginx `try_files $uri $uri/ /index.html`.
