# MVP Deployment Preparation (Phase 11)

Prepare **T-Ride MVP** for a **test/staging server** (e.g. Gabia cloud VPS). No new product features — configuration, layout, and verification only.

**Related:** [GABIA_STAGING_DEPLOY_CHECKLIST.md](./GABIA_STAGING_DEPLOY_CHECKLIST.md) (Phase 12 operator runbook) · [MVP_DEMO_GUIDE.md](./MVP_DEMO_GUIDE.md) · [MVP_DEV_SETUP.md](./MVP_DEV_SETUP.md) · [MVP_MANUAL_E2E_CHECKLIST.md](./MVP_MANUAL_E2E_CHECKLIST.md)

---

## 0. Local vs Gabia server (Phase 12)

| Location | Tasks |
|----------|--------|
| **Local / CI** | Run `npm test`, `flutter test`, `flutter build web --dart-define=API_BASE_URL=https://<domain>`, push git or create release tarball |
| **Gabia VPS** | Install Node 22 / nginx / PM2, write `backend/.env`, `./database/migrate.sh`, `npm ci`, PM2, copy `build/web`, nginx, seed, smoke |

**Operator checklist:** follow [GABIA_STAGING_DEPLOY_CHECKLIST.md](./GABIA_STAGING_DEPLOY_CHECKLIST.md) step-by-step.

---

## 1. Readiness summary

| Area | Status | Notes |
|------|--------|-------|
| Backend `npm start` | Ready | `src/server.js` → Express on `PORT` (default 3000) |
| Env validation | Ready | Joi in `src/config/env.js`; **staging/production** enforce strong JWT, DB password, explicit CORS |
| CORS | Ready | Comma-separated allowlist; localhost auto-allowed only in `development`/`test` |
| DB migrations | Ready | `database/migrate.ps1` (Windows) · **`database/migrate.sh`** (Linux/Gabia) |
| Flutter web build | Ready | `usePathUrlStrategy()` in `main.dart` |
| SPA deep links | Ready | `/booking/lookup`, `/admin`, `/driver` need `try_files … /index.html` |
| Uploads | Ready | Local disk under `UPLOAD_DIR`; **not** served as public static files — admin API download only |
| PM2 example | Ready | `deploy/pm2/ecosystem.config.cjs` |
| Nginx example | Ready | `deploy/nginx/ttaxi-staging.conf` (same-origin `/api/` proxy) |
| Demo seed | Staging OK | `seed:mvp-demo` blocked only when `NODE_ENV=production` |
| Secrets in Git | Safe | `.env` gitignored; `.env.example` placeholders only |

### Gaps / operator responsibilities

- **HTTPS** — example nginx config includes TLS; certificate install is manual (Phase 11+).
- **Linux migrate script** — use `./database/migrate.sh` (reads `backend/.env`); see [GABIA_STAGING_DEPLOY_CHECKLIST.md §G](./GABIA_STAGING_DEPLOY_CHECKLIST.md).
- **PM2 paths** — edit `cwd`, log paths in `deploy/pm2/ecosystem.config.cjs` to match server layout (`/srv/ttaxi/current/…`).
- **Same-origin vs split API** — choose one model below before setting `CORS_ORIGIN` and `API_BASE_URL`.

---

## 2. Recommended staging topology (Gabia)

### Option A — Single domain (recommended for MVP)

```
https://staging.example.com/          → Flutter static (nginx root)
https://staging.example.com/api/      → Node backend (nginx proxy → :3000)
https://staging.example.com/socket.io/→ Socket.IO (MVP demo does not require live sync)
```

| Setting | Value |
|---------|-------|
| `CORS_ORIGIN` | `https://staging.example.com` |
| Flutter build | `--dart-define=API_BASE_URL=https://staging.example.com` |
| Nginx | Use `deploy/nginx/ttaxi-staging.conf` |

Frontend calls `https://staging.example.com/api/v1/...` — same origin, simple CORS.

### Option B — Split frontend / API hostnames

```
https://app.staging.example.com   → Flutter static
https://api.staging.example.com   → Node backend (direct or nginx → :3000)
```

| Setting | Value |
|---------|-------|
| `CORS_ORIGIN` | `https://app.staging.example.com` |
| Flutter build | `--dart-define=API_BASE_URL=https://api.staging.example.com` |

---

## 3. Server layout (example)

```text
/srv/ttaxi/
  current/                 # git checkout or release tarball
    backend/
    frontend/build/web/    # after flutter build web
    database/
  shared/
    uploads/               # symlink or UPLOAD_DIR=/srv/ttaxi/shared/uploads
    logs/                  # optional; or /var/log/ttaxi
```

Create writable dirs before first start:

```bash
sudo mkdir -p /var/lib/ttaxi/uploads /var/log/ttaxi
sudo chown -R deploy:deploy /var/lib/ttaxi /var/log/ttaxi
```

Readiness probe checks DB + upload directory writable (`GET /api/v1/health/readiness`).

---

## 4. Backend deployment

### 4.1 Environment file

On the server:

```bash
cd /srv/ttaxi/current/backend
cp .env.example .env
# edit .env — never commit
```

**Staging minimum** (`NODE_ENV=staging`):

```env
NODE_ENV=staging
PORT=3000
TZ=Asia/Bangkok

DB_HOST=127.0.0.1
DB_PORT=3306
DB_NAME=ttaxi_staging
DB_USER=ttaxi_app
DB_PASSWORD=<strong-password>

JWT_ACCESS_SECRET=<random-32+-chars>
JWT_REFRESH_SECRET=<random-32+-chars>

CORS_ORIGIN=https://staging.example.com
PUBLIC_API_URL=https://staging.example.com

UPLOAD_DIR=/var/lib/ttaxi/uploads
LOG_DIR=/var/log/ttaxi
LOG_LEVEL=info

SWAGGER_ENABLED=false
FLIGHT_SYNC_ENABLED=false
ALLOW_DEV_QR_REISSUE=false
```

Full template: `backend/.env.example`

**Production/staging validation** (app exits on boot if violated):

- Weak or placeholder JWT secrets
- Empty `DB_PASSWORD`
- `CORS_ORIGIN=*` or empty
- `ALLOW_DEV_QR_REISSUE=true`

### 4.2 Install and start

```bash
cd /srv/ttaxi/current/backend
npm ci --omit=dev
npm start                    # foreground test
# or PM2:
pm2 start /srv/ttaxi/current/deploy/pm2/ecosystem.config.cjs --env staging
pm2 save
```

PM2 uses **one fork instance** (safe for flight-sync worker / outbox — do not cluster without review).

### 4.3 Scripts reference

| Script | Purpose |
|--------|---------|
| `npm start` | Production/staging server |
| `npm run dev` | Local watch mode |
| `npm test` | Unit/integration tests |
| `npm run validate:migrations` | Migration order check |
| `npm run seed:mvp-demo` | Demo accounts + bookings (**not** on production DB) |
| `npm run rehearsal:mvp-e2e` | API E2E against running DB |
| `npm run smoke:staging` | Post-deploy HTTP smoke (needs env URLs) |

---

## 5. Frontend deployment

### 5.1 Build (on CI machine or server with Flutter SDK)

**Same domain as API (Option A):**

```powershell
cd frontend
flutter pub get
flutter build web --release `
  --dart-define=API_BASE_URL=https://staging.example.com
```

**Split API (Option B):**

```powershell
flutter build web --release `
  --dart-define=API_BASE_URL=https://api.staging.example.com
```

Output: `frontend/build/web/` → copy to nginx `root`.

### 5.2 Path URLs / SPA fallback

`main.dart` calls `usePathUrlStrategy()`. Direct navigation must fall back to `index.html`:

| Route | Purpose |
|-------|---------|
| `/` | Customer landing |
| `/booking/lookup` | Guest status lookup |
| `/admin` | Admin dispatch (Reservations tab) |
| `/driver` | Driver login |

Nginx (included in example config):

```nginx
location / {
    try_files $uri $uri/ /index.html;
}
```

Without this, refreshing `/admin` returns 404 from nginx.

### 5.3 Optional dart-define (not required for MVP demo)

| Define | When |
|--------|------|
| `API_BASE_URL` | **Required** for non-localhost deploy |
| `SOCKET_URL` | Only if Socket.IO client used (MVP guest flow uses manual refresh) |
| `FIREBASE_*` | Push notifications — optional |

---

## 6. CORS

Implementation: `backend/src/config/cors.js`

| Environment | Behaviour |
|-------------|-----------|
| `development` / `test` | Allowlist **plus** any `http(s)://localhost:*` / `127.0.0.1:*` |
| `staging` / `production` | **Only** origins listed in `CORS_ORIGIN` |

**Multiple origins** (comma-separated, no spaces required but trim-safe):

```env
CORS_ORIGIN=https://staging.example.com,https://www.staging.example.com
```

Allowed headers include `Authorization` and `X-Guest-Access-Token` (guest lookup).

Socket.IO uses the same CORS policy (`server.js`).

---

## 7. Database (MySQL 8.x)

### 7.1 Create database and user

```sql
CREATE DATABASE ttaxi_staging CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'ttaxi_app'@'localhost' IDENTIFIED BY 'strong-password';
GRANT ALL PRIVILEGES ON ttaxi_staging.* TO 'ttaxi_app'@'localhost';
FLUSH PRIVILEGES;
```

### 7.2 Apply migrations

**Windows (repo script):**

```powershell
cd database
.\migrate.ps1   # reads backend\.env for DB_* 
```

**Linux (manual):** apply `database/*.sql` in lexicographic filename order (see `npm run validate:migrations` output). Do **not** skip numbered files.

### 7.3 Demo seed (staging test only)

```bash
cd backend
NODE_ENV=staging npm run seed:mvp-demo
```

- Creates `admin@ttaxi.dev`, driver `+66810000001`, six status-scenario bookings.
- **Refused** when `NODE_ENV=production`.
- Re-running creates **new** booking numbers — safe for test DB, avoid on shared staging if others depend on fixed IDs.

### 7.4 DB separation

| DB | Use |
|----|-----|
| `ttaxi` / local | Developer machines |
| `ttaxi_staging` | Test/staging server |
| `ttaxi_prod` | Future production (no demo seed) |

Never point staging `.env` at production MySQL. **No automated DB reset** in repo — drops are manual.

---

## 8. File uploads

| Item | Detail |
|------|--------|
| Driver application attachments | `POST /api/v1/driver-applications` (multipart) |
| Settlement receipts | Driver upload API |
| Storage path | `UPLOAD_DIR` (default `./uploads`; staging: `/var/lib/ttaxi/uploads`) |
| Layout | `YYYY-MM-DD/` subfolders, random filenames |
| Public HTTP | **No** — files served via authenticated admin routes only |
| Git | `backend/uploads/` gitignored |
| Backup | Include `UPLOAD_DIR` in server backup if driver applications matter |
| Permissions | Process user must write to `UPLOAD_DIR`; readiness check verifies |

---

## 9. Logging

| Setting | Default | Staging suggestion |
|---------|---------|-------------------|
| `LOG_LEVEL` | `info` | `info` or `warn` |
| `LOG_DIR` | `./logs` | `/var/log/ttaxi` |

Winston writes `error.log`, `combined.log`, and console (JSON in `production`, colorized in dev/staging).

---

## 10. Gabia manual deploy checklist

1. [ ] Provision VPS — Node 22+, MySQL 8.4, nginx, PM2 optional
2. [ ] Clone/upload repo to `/srv/ttaxi/current`
3. [ ] Create MySQL database + user
4. [ ] Run migrations
5. [ ] `backend/.env` from `.env.example` (staging values, strong secrets)
6. [ ] Create `/var/lib/ttaxi/uploads`, `/var/log/ttaxi`
7. [ ] `cd backend && npm ci --omit=dev`
8. [ ] `npm start` or PM2 — verify `GET /api/v1/health`
9. [ ] `flutter build web` with correct `API_BASE_URL`
10. [ ] Copy `frontend/build/web` → nginx root
11. [ ] Install `deploy/nginx/ttaxi-staging.conf` (edit `server_name`, paths, SSL paths)
12. [ ] `nginx -t && systemctl reload nginx`
13. [ ] Optional: `NODE_ENV=staging npm run seed:mvp-demo`
14. [ ] Run verification commands (§11)
15. [ ] Manual UI walkthrough — [MVP_MANUAL_E2E_CHECKLIST.md](./MVP_MANUAL_E2E_CHECKLIST.md)

HTTPS: example config redirects 80→443. For initial HTTP-only smoke, temporarily comment SSL server block or use self-signed cert.

---

## 11. Verification commands

**On build machine / CI:**

```powershell
cd backend
npm test
npm run validate:migrations

cd ..\frontend
flutter test
flutter build web --release --dart-define=API_BASE_URL=https://staging.example.com
```

**Against staging server (after deploy):**

```powershell
cd backend
$env:STAGING_BASE_URL="https://staging.example.com"
$env:STAGING_FRONTEND_URL="https://staging.example.com"
npm run smoke:staging

npm run seed:mvp-demo          # staging DB only
npm run rehearsal:mvp-e2e      # needs DB + demo accounts
```

Expected baselines (2026-07-04):

| Command | Expected |
|---------|----------|
| `npm test` | 428 pass |
| `flutter test` | 250 pass |
| `npm run rehearsal:mvp-e2e` | 19/19 pass |
| `npm run smoke:staging` | Exit 0 when URLs reachable |

**Browser smoke:**

- https://staging.example.com/booking/lookup
- https://staging.example.com/admin
- https://staging.example.com/driver

---

## 12. Known MVP limitations (ship as-is)

Document for stakeholders — not deployment blockers:

- No payment processing
- No customer signup (guest booking + lookup only)
- No chat in demo UI
- No QR boarding/completion in demo UI
- No Socket.IO live guest sync (manual **Refresh** on lookup)
- No auto-dispatch (admin manual assign)
- No driver live GPS map
- Guest lookup rate limit: 10 req/min/IP in production mode

---

## 13. Security reminders

- Never commit `backend/.env`, upload files, or Firebase JSON keys
- Rotate demo passwords if staging is internet-facing
- Set `SWAGGER_ENABLED=false` on public staging
- Keep `ALLOW_DEV_QR_REISSUE=false` on staging/production
- Use `NODE_ENV=staging` on test servers (not `development`) so localhost CORS bypass is disabled

---

## 14. Reference files

| Path | Purpose |
|------|---------|
| **[GABIA_STAGING_DEPLOY_CHECKLIST.md](./GABIA_STAGING_DEPLOY_CHECKLIST.md)** | **Phase 12 — step-by-step Gabia deploy** |
| `database/migrate.sh` | Linux migration runner |
| `backend/.env.example` | Env template + staging comments |
| `backend/src/config/env.js` | Validation rules |
| `backend/src/config/cors.js` | CORS allowlist |
| `deploy/nginx/ttaxi-staging.conf` | HTTPS + SPA fallback |
| `deploy/nginx/ttaxi-staging-http.conf` | HTTP-only first boot |
| `deploy/nginx/README.md` | nginx file guide |
| `deploy/pm2/ecosystem.config.cjs` | PM2 process definition |
| `backend/scripts/staging-smoke-test.js` | Post-deploy HTTP checks |
| `backend/tests/deploymentReadiness.test.js` | CI guardrails for deploy artifacts |

---

## 15. Phase 12 execution checklist (summary)

Copy of deploy order — full commands in [GABIA_STAGING_DEPLOY_CHECKLIST.md](./GABIA_STAGING_DEPLOY_CHECKLIST.md):

1. [ ] Gabia VPS: Node 22, nginx, mysql-client, PM2
2. [ ] Code at `/srv/ttaxi/current`
3. [ ] MySQL: `ttaxi_staging` + app user
4. [ ] `backend/.env` (chmod 600, strong secrets)
5. [ ] `./database/migrate.sh`
6. [ ] `npm ci --omit=dev` → PM2 `--env staging`
7. [ ] `flutter build web --dart-define=API_BASE_URL=https://<domain>`
8. [ ] nginx (HTTP first, then HTTPS) → `nginx -t` → reload
9. [ ] `seed:mvp-demo` (staging only)
10. [ ] `npm run smoke:staging` + `npm run rehearsal:mvp-e2e`
11. [ ] Manual UI checklist A–F
