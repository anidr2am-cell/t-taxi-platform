# MVP Deployment Preparation (Phase 11–12)

Prepare **T-Ride MVP** for **tride-staging** on the **Gabia VPS** that already runs the legacy **KTaxi/TTaxi** stack. No new product features — configuration, layout, and verification only.

**Operator runbook:** [GABIA_STAGING_DEPLOY_CHECKLIST.md](./GABIA_STAGING_DEPLOY_CHECKLIST.md)  
**Also:** [MVP_DEMO_GUIDE.md](./MVP_DEMO_GUIDE.md) · [MVP_DEV_SETUP.md](./MVP_DEV_SETUP.md) · [MVP_MANUAL_E2E_CHECKLIST.md](./MVP_MANUAL_E2E_CHECKLIST.md)

---

## 0. Two projects — naming and boundaries

This repo (`C:\TTaxi` locally) builds **T-Ride**, not the legacy KTaxi web. On the shared Gabia server both stacks run **side by side** with **separate** paths, containers, databases, and domains.

| | **Legacy KTaxi / TTaxi (untouched)** | **T-Ride MVP (this deploy)** |
|---|--------------------------------------|------------------------------|
| Server path | `/opt/ktaxi` | **`/opt/t-ride`** |
| Compose | `/opt/ktaxi/infra/docker-compose.yml` | **`deploy/docker/docker-compose.staging.yml`** |
| Containers | `ktaxi-*` | **`tride-*`** |
| Network | (ktaxi internal) | **`tride-net`** |
| Database | Postgres (`ktaxi-postgres`) | **MySQL** (`tride-db`, DB **`tride_staging`**) |
| Public edge | **`ktaxi-nginx`** → host **80/443** | **`tride-staging.88taxi.net`** via ktaxi-nginx (Phase 5) |
| Legacy domains | `88taxi.net`, `driver.`, `admin.`, `api.`, `ws.` | — |

**Gabia server facts (do not assume otherwise):**

- Docker: **yes**
- Host nginx / PM2 / Node: **no**
- `ktaxi-nginx` already binds host **80/443**

**Never:** modify `/opt/ktaxi`, restart `ktaxi-*`, install host nginx on 80/443, or migrate T-Ride against `ktaxi-postgres`.

---

## 1. Readiness summary

| Area | Status | Notes |
|------|--------|-------|
| Backend `npm start` | Ready | Express on `PORT` (default 3000) — runs **inside** `tride-backend` container |
| Env validation | Ready | Joi in `src/config/env.js`; staging/production enforce strong JWT, DB password, explicit CORS |
| CORS | Ready | Comma-separated allowlist; localhost bypass only in `development`/`test` |
| DB migrations | Ready | `database/migrate.ps1` (Windows) · **`database/migrate.sh`** (Linux / Docker exec) |
| Flutter web build | Ready | `usePathUrlStrategy()` in `main.dart` |
| SPA deep links | Ready | `/booking/lookup`, `/admin`, `/driver` need nginx `try_files … /index.html` |
| Uploads | Ready | Local disk under `UPLOAD_DIR`; bind-mount **`/opt/t-ride/uploads`** on Gabia |
| Docker Compose | Ready | `deploy/docker/docker-compose.staging.yml` + Dockerfiles |
| PM2 example | Reference only | `deploy/pm2/ecosystem.config.cjs` — **not used on Gabia** (no host Node) |
| Nginx examples | Reference only | `deploy/nginx/ttaxi-staging*.conf` — for standalone VPS or **inside** `tride-frontend`; **not** host install on Gabia |
| Demo seed | Staging OK | `seed:mvp-demo` blocked when `NODE_ENV=production` |
| Secrets in Git | Safe | `.env` gitignored; `.env.example` placeholders only |

### Gaps / operator responsibilities

- Copy `deploy/docker/.env.example` → `deploy/docker/.env` on the server before first `up`.
- **Phase 1–3** — split-port smoke: API **`:3100`**, UI **`:3101`** — no ktaxi changes.
- **Phase 4–5** — ktaxi-nginx vhost for `tride-staging.88taxi.net` → host **`:3101`** (future step only).
- **Split-origin smoke** — `CORS_ORIGIN` = frontend `:3101`, `TRIDE_API_BASE_URL` = backend `:3100`.

---

## 2. Gabia staging topology

### 2.1 Coexistence (both stacks on one host)

```text
                    Internet
                        │
                        ▼
              ┌─────────────────────┐
              │   ktaxi-nginx       │  host :80 / :443  (DO NOT REPLACE)
              │   (existing)        │
              └─────────┬───────────┘
                        │
        ┌───────────────┼───────────────────────────────┐
        │               │                               │
        ▼               ▼                               ▼
  88taxi.net      api.88taxi.net              tride-staging.88taxi.net
  driver/admin/   ws.88taxi.net               (Phase 5 — new vhost only)
  ws …            ktaxi-api :8787                      │
  (ktaxi stack)   ktaxi-realtime :8788                  │ proxy_pass
        │               │                               ▼
        │         ktaxi-postgres                 host :3101 (frontend)
        │         (/opt/ktaxi)                   host :3100 (API debug)
        │                                               │
        │                                               ▼
        │                              ┌────────────────────────────┐
        │                              │  T-Ride stack (/opt/t-ride) │
        │                              │  compose: deploy/docker/    │
        │                              │  network: tride-net         │
        │                              │  tride-frontend :80 → :3101 │
        │                              │  tride-backend :3000 → :3100│
        │                              │  tride-db (MySQL 8.4)       │
        │                              │  DB: tride_staging          │
        │                              └────────────────────────────┘
        │
        └── Legacy KTaxi — never stop for T-Ride deploy
```

### 2.2 T-Ride routing — split-port smoke (Phase 2)

```text
http://SERVER_IP:3100/api/v1/…   → tride-backend:3000 (direct API)
http://SERVER_IP:3101/           → tride-frontend (Flutter static)
http://SERVER_IP:3101/booking/lookup  → SPA deep link
```

| Setting | Phase 2 (split ports) | Phase 5 (public domain) |
|---------|----------------------|-------------------------|
| `CORS_ORIGIN` | `http://SERVER_IP:3101` | `https://tride-staging.88taxi.net` |
| `PUBLIC_API_URL` | `http://SERVER_IP:3100` | `https://tride-staging.88taxi.net` |
| `TRIDE_API_BASE_URL` | `http://SERVER_IP:3100` | `https://tride-staging.88taxi.net` |
| Browser UI | `:3101` | `tride-staging.88taxi.net` |

**Phase 5 (future — ktaxi-nginx):**

```text
https://tride-staging.88taxi.net/  → ktaxi-nginx → host:3101 → tride-frontend
```

`tride-frontend` nginx can proxy `/api/` → `tride-backend` for same-origin domain builds.

### 2.3 Alternative — standalone VPS (not Gabia)

If deploying T-Ride on a **dedicated** server with host nginx + PM2, use:

- Layout: `/srv/ttaxi/current` (historical example in `deploy/pm2/`)
- Config: `deploy/nginx/ttaxi-staging.conf`
- Domain: any staging hostname (e.g. `staging.example.com`)

That model is **not** the Gabia plan documented here.

---

## 3. Server layout — `/opt/t-ride`

```text
/opt/t-ride/
  backend/
  frontend/
  database/
  deploy/
    docker/
      docker-compose.staging.yml
      .env.example
  uploads/                    # optional bind-mount (see deploy/docker/README.md)
```

Create before first `docker compose up`:

```bash
sudo mkdir -p /opt/t-ride/uploads
sudo chown -R "$USER":"$USER" /opt/t-ride
cd /opt/t-ride/deploy/docker
cp .env.example .env && chmod 600 .env
```

Readiness probe: `GET /api/v1/health/readiness` checks DB + writable `UPLOAD_DIR`.

**Do not use:** `/srv/ttaxi`, `/opt/ktaxi`, or `ttaxi_staging` DB name on Gabia.

---

## 4. Backend deployment (Docker)

### 4.1 Environment file

On the server, configure **`deploy/docker/.env`** (see `deploy/docker/.env.example`). Compose injects vars into **`tride-backend`** — no separate host `npm start` required.

**T-Ride staging minimum** (`NODE_ENV=staging`):

```env
MYSQL_ROOT_PASSWORD=replace-with-strong-root-password
DB_NAME=tride_staging
DB_USER=tride_app
DB_PASSWORD=replace-with-strong-database-password

JWT_ACCESS_SECRET=replace-with-strong-random-access-secret
JWT_REFRESH_SECRET=replace-with-strong-random-refresh-secret

CORS_ORIGIN=http://SERVER_IP:3101
PUBLIC_API_URL=http://SERVER_IP:3100
TRIDE_API_BASE_URL=http://SERVER_IP:3100

TRIDE_BACKEND_HOST_PORT=3100
TRIDE_FRONTEND_HOST_PORT=3101
```

Full template: `backend/.env.example`

**Validation on boot** (staging/production): weak JWT, empty `DB_PASSWORD`, wildcard CORS, `ALLOW_DEV_QR_REISSUE=true` → process exits.

### 4.2 Start (Gabia — Docker)

```bash
cd /opt/t-ride/deploy/docker
docker compose -f docker-compose.staging.yml up -d --build
docker compose -f docker-compose.staging.yml ps
docker compose -f docker-compose.staging.yml logs -f tride-backend
```
```

**Not used on Gabia:** `npm start` on host, PM2, host Node 22 install.

Reference PM2 config (`deploy/pm2/ecosystem.config.cjs`) remains for non-Docker VPS only.

### 4.3 Scripts reference

| Script | Purpose |
|--------|---------|
| `npm start` | Server entry (inside container) |
| `npm test` | Unit/integration tests (local/CI) |
| `npm run validate:migrations` | Migration order check |
| `npm run seed:mvp-demo` | Demo accounts + bookings (**tride_staging** only) |
| `npm run rehearsal:mvp-e2e` | API E2E against running DB |
| `npm run smoke:staging` | Post-deploy HTTP smoke (`STAGING_*_URL` env) |

Run seed/rehearsal via:

```bash
docker compose -f docker-compose.staging.yml exec tride-backend npm run seed:mvp-demo
docker compose -f docker-compose.staging.yml exec tride-backend npm run rehearsal:mvp-e2e
```

---

## 5. Frontend deployment

### 5.1 Build (local CI or dev machine)

**Phase 2 — split ports** (set `TRIDE_API_BASE_URL` in `deploy/docker/.env`; rebuild `tride-frontend`):

```powershell
# Local flutter build (optional — Docker build uses TRIDE_API_BASE_URL from .env)
cd frontend
flutter build web --release `
  --dart-define=API_BASE_URL=http://SERVER_IP:3100
```

**Phase 5 — public domain** (future ktaxi-nginx):

```powershell
flutter build web --release `
  --dart-define=API_BASE_URL=https://tride-staging.88taxi.net
```

Output is baked into **`tride-frontend`** via `deploy/docker/Dockerfile.frontend`.

### 5.2 Path URLs / SPA fallback

| Route | Purpose |
|-------|---------|
| `/` | Customer landing |
| `/booking/lookup` | Guest status lookup |
| `/admin` | Admin dispatch |
| `/driver` | Driver login |

**tride-frontend** nginx (same pattern as `deploy/nginx/ttaxi-staging-http.conf`):

```nginx
location / {
    try_files $uri $uri/ /index.html;
}
location /api/ {
    proxy_pass http://tride-backend:3000;
}
```

Without SPA fallback, refreshing `/admin` returns 404.

### 5.3 Optional dart-define

| Define | When |
|--------|------|
| `API_BASE_URL` | **Required** for non-localhost deploy |
| `SOCKET_URL` | Only if Socket.IO used (MVP guest flow uses manual refresh) |
| `FIREBASE_*` | Push — optional |

---

## 6. CORS

Implementation: `backend/src/config/cors.js`

| Environment | Behaviour |
|-------------|-----------|
| `development` / `test` | Allowlist **plus** localhost origins |
| `staging` / `production` | **Only** `CORS_ORIGIN` list |

```env
CORS_ORIGIN=https://tride-staging.88taxi.net
```

Allowed headers include `Authorization` and `X-Guest-Access-Token`.

When rebuilding frontend for a new public URL, update **both** `CORS_ORIGIN` and `API_BASE_URL`.

---

## 7. Database (MySQL 8.x — `tride-db` only)

### 7.1 Create database and user

Run against **`tride-db`**, not `ktaxi-postgres`:

```sql
CREATE DATABASE tride_staging CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'tride_app'@'%' IDENTIFIED BY 'REPLACE_WITH_STRONG_PASSWORD';
GRANT ALL PRIVILEGES ON tride_staging.* TO 'tride_app'@'%';
FLUSH PRIVILEGES;
```

### 7.2 Apply migrations

**Windows (local dev):**

```powershell
cd database
.\migrate.ps1
```

**Linux / Gabia Docker:**

```bash
cd /opt/t-ride/deploy/docker
docker compose -f docker-compose.staging.yml exec tride-backend \
  sh -c 'cd /srv/tride/database && ./migrate.sh'
```

Or host script: `./database/migrate.sh` (reads `backend/.env`).

Apply `database/*.sql` in lexicographic order — do not skip files.

### 7.3 Demo seed (tride_staging only)

```bash
docker compose -f docker-compose.staging.yml exec tride-backend npm run seed:mvp-demo
```

Creates `admin@ttaxi.dev`, driver `+66810000001`, six status-scenario bookings. **Refused** when `NODE_ENV=production`.

### 7.4 DB naming

| DB | Use |
|----|-----|
| `ttaxi` | Local developer machines |
| **`tride_staging`** | **Gabia T-Ride staging** (`tride-db`) |
| `ttaxi_prod` / future | Production T-Ride (separate deploy) |

Never point T-Ride `.env` at `ktaxi-postgres` or legacy KTaxi databases.

---

## 8. File uploads

| Item | Detail |
|------|--------|
| Storage | `UPLOAD_DIR=/srv/tride/uploads` in container; volume **`tride_uploads`** (optional bind: `/opt/t-ride/uploads`) |
| Public HTTP | **No** — admin API download only |
| Git | `backend/uploads/` gitignored |
| Permissions | `tride-backend` user must write mount; readiness check verifies |

---

## 9. Logging

| Setting | Default | T-Ride staging (Docker) |
|---------|---------|-------------------------|
| `LOG_LEVEL` | `info` | `info` |
| `LOG_DIR` | `./logs` | `/app/logs` (optional volume) |

View logs: `docker compose -f deploy/docker/docker-compose.staging.yml logs -f tride-backend`

---

## 10. Phased Gabia deploy checklist

Full commands: [GABIA_STAGING_DEPLOY_CHECKLIST.md](./GABIA_STAGING_DEPLOY_CHECKLIST.md)

| Phase | Goal | KTaxi impact |
|-------|------|--------------|
| **1** | Compose at `/opt/t-ride`, `tride-net`, `tride-*` containers | **None** |
| **2** | Smoke on host **:3100** / **:3101** | **None** |
| **3** | Migrate `tride_staging`, seed, rehearsal 19/19 | **None** |
| **4** | Review ktaxi-nginx plan for `tride-staging.88taxi.net` | **None** (plan only) |
| **5** | Add vhost + TLS; rebuild Flutter for HTTPS domain | **Reload ktaxi-nginx only** — verify `88taxi.net` unchanged |

---

## 11. Verification commands

**Local / CI (before server deploy):**

```powershell
cd backend
npm test
npm run validate:migrations

cd ..\frontend
flutter test
flutter build web --release `
  --dart-define=API_BASE_URL=http://SERVER_IP:3100
```

**Against Gabia (Phase 2):**

```bash
curl -s http://SERVER_IP:3100/api/v1/health
curl -s http://SERVER_IP:3100/api/v1/health/readiness
curl -s -o /dev/null -w "%{http_code}\n" http://SERVER_IP:3101/booking/lookup
```

```powershell
cd backend
$env:STAGING_BASE_URL="http://SERVER_IP:3100"
$env:STAGING_FRONTEND_URL="http://SERVER_IP:3101"
npm run smoke:staging
```

```bash
cd /opt/t-ride/deploy/docker
docker compose -f docker-compose.staging.yml exec tride-backend npm run rehearsal:mvp-e2e
```

**Phase 5 browser smoke:**

- `https://tride-staging.88taxi.net/booking/lookup`
- `https://tride-staging.88taxi.net/admin`
- `https://tride-staging.88taxi.net/driver`
- Confirm **`https://88taxi.net/`** still serves legacy KTaxi

Expected baselines:

| Command | Expected |
|---------|----------|
| `npm test` | 428 pass |
| `flutter test` | 250 pass |
| `npm run rehearsal:mvp-e2e` | 19/19 pass |
| `npm run smoke:staging` | Exit 0 when URLs reachable |

---

## 12. Known MVP limitations (ship as-is)

- No payment processing
- No customer signup (guest booking + lookup only)
- No chat / QR / Socket.IO live sync in demo UI
- No auto-dispatch (admin manual assign)
- No driver live GPS map
- Guest lookup rate limit: stricter in production mode

---

## 13. Security reminders

- Never commit `backend/.env`, upload files, or API keys
- Rotate demo passwords if staging is internet-facing
- `SWAGGER_ENABLED=false`, `ALLOW_DEV_QR_REISSUE=false` on staging
- Use `NODE_ENV=staging` (not `development`) on Gabia
- ktaxi-nginx changes: backup config before Phase 5; rollback if legacy sites break

---

## 14. Reference files

| Path | Purpose |
|------|---------|
| **[GABIA_STAGING_DEPLOY_CHECKLIST.md](./GABIA_STAGING_DEPLOY_CHECKLIST.md)** | **Primary Gabia operator runbook** |
| **[deploy/docker/README.md](../deploy/docker/README.md)** | **Compose usage, smoke ports, migrate/seed** |
| `deploy/docker/docker-compose.staging.yml` | Staging stack definition |
| `deploy/docker/Dockerfile.backend` | Node 22 backend image |
| `deploy/docker/Dockerfile.frontend` | Flutter web + nginx image |
| `deploy/docker/.env.example` | Staging env template |
| `database/migrate.sh` | Linux migration runner |
| `backend/.env.example` | Env template |
| `backend/src/config/env.js` | Validation rules |
| `deploy/nginx/ttaxi-staging*.conf` | **Reference** — SPA + `/api/` proxy pattern (tride-frontend or standalone VPS) |
| `deploy/nginx/README.md` | Notes: **not for host install on Gabia** |
| `deploy/pm2/ecosystem.config.cjs` | **Reference** — non-Docker VPS only |
| `backend/scripts/staging-smoke-test.js` | Post-deploy HTTP checks |
| `backend/tests/deploymentReadiness.test.js` | CI guardrails |

---

## 15. Phase 12 execution summary

1. [ ] Confirm `ktaxi-*` running; **do not** modify `/opt/ktaxi`
2. [ ] Clone repo to **`/opt/t-ride`**
3. [ ] `deploy/docker/.env` from `.env.example`
4. [ ] `docker compose -f deploy/docker/docker-compose.staging.yml up -d --build`
5. [ ] Migrate + seed on **`tride_staging`** only
6. [ ] Smoke API **:3100**, UI **:3101**
7. [ ] `rehearsal:mvp-e2e` + `smoke:staging`
8. [ ] Manual E2E A–F
9. [ ] *(Future)* ktaxi-nginx plan for **`tride-staging.88taxi.net`**
