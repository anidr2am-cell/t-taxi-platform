# Gabia Staging Deploy Checklist (Phase 12)

Operator runbook for **T-Ride MVP** on a **Gabia Linux VPS** (single domain).

> Replace every `staging.example.com` with your real staging hostname.  
> **Never** paste real passwords or JWT secrets into Git, docs, or chat logs.

**Prerequisites docs:** [MVP_DEPLOYMENT_PREP.md](./MVP_DEPLOYMENT_PREP.md) · [MVP_DEMO_GUIDE.md](./MVP_DEMO_GUIDE.md) · [MVP_MANUAL_E2E_CHECKLIST.md](./MVP_MANUAL_E2E_CHECKLIST.md)

---

## A. Work split — local vs Gabia server

| Where | What |
|-------|------|
| **Local / CI** | `git push`, `flutter build web`, optional `npm test`, upload release tarball or `git pull` on server |
| **Gabia VPS** | Node/MySQL/nginx/PM2 install, `.env`, migrate, `npm ci`, PM2, nginx, seed, smoke, browser check |

---

## B. Variables (fill before deploy)

| Symbol | Example placeholder | Your value |
|--------|---------------------|------------|
| `STAGING_DOMAIN` | `staging.example.com` | |
| `DEPLOY_USER` | `deploy` | |
| `APP_ROOT` | `/srv/ttaxi/current` | |
| `DB_NAME` | `ttaxi_staging` | |
| `DB_USER` | `ttaxi_app` | |

---

## C. Gabia server — first-time setup

SSH as root or sudo user, then:

### C1. OS packages

```bash
sudo apt update
sudo apt install -y curl git nginx mysql-client

# Node.js 22 (NodeSource — verify version on your image)
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt install -y nodejs

node -v    # expect v22.x
npm -v
```

### C2. PM2 (global)

```bash
sudo npm install -g pm2
pm2 -v
```

### C3. MySQL 8.x

Use Gabia managed MySQL **or** local MySQL on VPS. Confirm client works:

```bash
mysql --version
mysql -h 127.0.0.1 -u root -p -e "SELECT VERSION();"
```

### C4. Deploy user & directories

```bash
sudo useradd -m -s /bin/bash deploy || true
sudo mkdir -p /srv/ttaxi/current /var/lib/ttaxi/uploads /var/log/ttaxi
sudo chown -R deploy:deploy /srv/ttaxi /var/lib/ttaxi /var/log/ttaxi
```

### C5. Firewall (if ufw enabled)

```bash
sudo ufw allow OpenSSH
sudo ufw allow 'Nginx Full'
sudo ufw enable
sudo ufw status
```

---

## D. Deploy application code

As `deploy` user:

```bash
sudo su - deploy
cd /srv/ttaxi

# Option 1 — git
git clone https://github.com/anidr2am-cell/t-taxi-platform.git current
cd current

# Option 2 — upload tarball from local machine, then:
# tar xzf ttaxi-release.tgz -C /srv/ttaxi/current
```

---

## E. MySQL — database & user

Connect as MySQL admin (adjust host if remote):

```bash
mysql -h 127.0.0.1 -u root -p
```

```sql
CREATE DATABASE ttaxi_staging CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE USER 'ttaxi_app'@'localhost' IDENTIFIED BY 'REPLACE_WITH_STRONG_PASSWORD';
GRANT ALL PRIVILEGES ON ttaxi_staging.* TO 'ttaxi_app'@'localhost';
FLUSH PRIVILEGES;
EXIT;
```

Test app user:

```bash
mysql -h 127.0.0.1 -u ttaxi_app -p ttaxi_staging -e "SELECT 1;"
```

---

## F. Backend `.env`

```bash
cd /srv/ttaxi/current/backend
cp .env.example .env
chmod 600 .env
nano .env   # or vim — never commit this file
```

**Staging template** (replace placeholders only on the server):

```env
NODE_ENV=staging
PORT=3000
TZ=Asia/Bangkok
API_VERSION=v1
APP_NAME=T-Ride

DB_HOST=127.0.0.1
DB_PORT=3306
DB_NAME=ttaxi_staging
DB_USER=ttaxi_app
DB_PASSWORD=REPLACE_WITH_STRONG_PASSWORD
DB_CONNECTION_LIMIT=10

JWT_ACCESS_SECRET=REPLACE_WITH_RANDOM_32_PLUS_CHARS
JWT_REFRESH_SECRET=REPLACE_WITH_RANDOM_32_PLUS_CHARS
JWT_ACCESS_EXPIRES_IN=1h
JWT_REFRESH_EXPIRES_IN=7d

CORS_ORIGIN=https://STAGING_DOMAIN
PUBLIC_API_URL=https://STAGING_DOMAIN

UPLOAD_DIR=/var/lib/ttaxi/uploads
UPLOAD_MAX_FILE_SIZE_MB=10
LOG_LEVEL=info
LOG_DIR=/var/log/ttaxi

SWAGGER_ENABLED=false
FLIGHT_SYNC_ENABLED=false
ALLOW_DEV_QR_REISSUE=false
SOCKET_PATH=/socket.io
```

Generate secrets on the server (example):

```bash
openssl rand -base64 48
```

Validate env loads:

```bash
cd /srv/ttaxi/current/backend
node -e "require('./src/config/env'); console.log('env ok')"
```

---

## G. Database migrations

```bash
cd /srv/ttaxi/current/database
chmod +x migrate.sh
./migrate.sh
# reads ../backend/.env automatically
```

Windows alternative: run `migrate.ps1` from a dev machine pointing at staging DB (not recommended for production DB).

Verify:

```bash
mysql -h 127.0.0.1 -u ttaxi_app -p ttaxi_staging -e "SHOW TABLES LIKE 'bookings';"
```

---

## H. Backend install & PM2

```bash
cd /srv/ttaxi/current/backend
npm ci --omit=dev

# Foreground smoke (Ctrl+C after OK)
npm start
# In another SSH session:
curl -s http://127.0.0.1:3000/api/v1/health | head
```

PM2 (edit paths in `deploy/pm2/ecosystem.config.cjs` if `APP_ROOT` differs):

```bash
cd /srv/ttaxi/current
pm2 start deploy/pm2/ecosystem.config.cjs --env staging
pm2 save
pm2 startup    # run the command it prints (sudo)
pm2 status
pm2 logs ttaxi-api-staging --lines 50
```

Readiness (503 until DB + uploads OK):

```bash
curl -s http://127.0.0.1:3000/api/v1/health/readiness
```

---

## I. Frontend build & deploy

**On a machine with Flutter SDK** (local or CI):

```powershell
cd frontend
flutter pub get
flutter build web --release `
  --dart-define=API_BASE_URL=https://STAGING_DOMAIN
```

Copy `frontend/build/web/` to server:

```bash
# from local (example)
scp -r frontend/build/web deploy@STAGING_DOMAIN:/srv/ttaxi/current/frontend/build/
```

Or build on server if Flutter is installed there.

Confirm files:

```bash
ls /srv/ttaxi/current/frontend/build/web/index.html
```

---

## J. nginx

### J1. HTTP first (no TLS yet)

Edit domain and root in repo file, then:

```bash
sudo sed -e 's/staging.example.com/STAGING_DOMAIN/g' \
  /srv/ttaxi/current/deploy/nginx/ttaxi-staging-http.conf \
  | sudo tee /etc/nginx/sites-available/ttaxi-staging

sudo ln -sf /etc/nginx/sites-available/ttaxi-staging /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl reload nginx
```

### J2. HTTPS (after certbot)

```bash
# After certificates exist under /etc/letsencrypt/live/STAGING_DOMAIN/
sudo cp /srv/ttaxi/current/deploy/nginx/ttaxi-staging.conf /etc/nginx/sites-available/ttaxi-staging
# edit server_name + ssl_certificate paths
sudo nginx -t
sudo systemctl reload nginx
```

Update `CORS_ORIGIN` and rebuild frontend if you switch HTTP → HTTPS.

### J3. SPA routes to verify

| URL | Expected |
|-----|----------|
| `https://STAGING_DOMAIN/` | Landing |
| `https://STAGING_DOMAIN/booking/lookup` | Guest lookup form |
| `https://STAGING_DOMAIN/admin` | Admin dispatch login |
| `https://STAGING_DOMAIN/driver` | Driver login |

---

## K. Demo seed (staging test DB only)

```bash
cd /srv/ttaxi/current/backend
NODE_ENV=staging npm run seed:mvp-demo
```

Save printed booking numbers. Demo accounts:

| Role | Login | Password (dev default) |
|------|-------|------------------------|
| Admin | `admin@ttaxi.dev` | `Admin123456!` |
| Driver | `+66810000001` | `Driver123456!` |

Change demo passwords if staging is public.

---

## L. Automated smoke tests

From any machine that can reach staging:

```bash
cd backend
export STAGING_BASE_URL=https://STAGING_DOMAIN
export STAGING_FRONTEND_URL=https://STAGING_DOMAIN
npm run smoke:staging
```

On server (full API rehearsal against DB):

```bash
cd /srv/ttaxi/current/backend
npm run rehearsal:mvp-e2e
# expect 19/19 pass
```

---

## M. Operator manual verification

Use [MVP_MANUAL_E2E_CHECKLIST.md](./MVP_MANUAL_E2E_CHECKLIST.md) sections **A–F**:

- [ ] Customer booking wizard → complete page
- [ ] Guest lookup + Refresh after driver status change
- [ ] Admin assign driver
- [ ] Driver ON_ROUTE → ARRIVED → COMPLETED
- [ ] Cancelled seed guidance (optional)

---

## N. Rollback & troubleshooting

### Stop / rollback app

```bash
pm2 stop ttaxi-api-staging
# restore previous release directory, then:
pm2 restart ttaxi-api-staging
```

### Logs

| Source | Command |
|--------|---------|
| PM2 stdout/stderr | `pm2 logs ttaxi-api-staging` |
| PM2 files | `tail -f /var/log/ttaxi/api-error.log` |
| Backend winston | `tail -f /var/log/ttaxi/combined.log` |
| nginx error | `sudo tail -f /var/log/nginx/ttaxi-staging-error.log` |
| nginx access | `sudo tail -f /var/log/nginx/ttaxi-staging-access.log` |

### Common issues

| Symptom | Check |
|---------|--------|
| 502 on `/api/` | `pm2 status`; `curl localhost:3000/api/v1/health` |
| SPA 404 on refresh | nginx `try_files … /index.html` in `location /` |
| CORS error in browser | `CORS_ORIGIN` must match `https://STAGING_DOMAIN` exactly |
| Env boot failure | `node -e "require('./src/config/env')"` — weak JWT or missing DB password |
| Readiness 503 | DB credentials; `UPLOAD_DIR` writable by PM2 user |
| Wrong API host in UI | Rebuild with `--dart-define=API_BASE_URL=https://STAGING_DOMAIN` |
| MySQL refused | `systemctl status mysql`; security group / bind-address |

### MySQL connectivity

```bash
mysql -h 127.0.0.1 -u ttaxi_app -p ttaxi_staging -e "SELECT 1;"
cd /srv/ttaxi/current/backend && node -e "require('./src/config/database').ping().then(console.log)"
```

---

## O. Required environment variables (summary)

| Variable | Required | Notes |
|----------|----------|-------|
| `NODE_ENV` | Yes | `staging` on test server |
| `PORT` | Yes | `3000` (internal; nginx proxies) |
| `DB_*` | Yes | Host, name, user, password |
| `JWT_*_SECRET` | Yes | Strong random, ≥16 chars |
| `CORS_ORIGIN` | Yes | `https://STAGING_DOMAIN` |
| `UPLOAD_DIR` | Yes | Writable path |
| `LOG_DIR` | Recommended | `/var/log/ttaxi` |
| `PUBLIC_API_URL` | Optional | Same as staging domain |
| `GOOGLE_MAPS_API_KEY` | Optional | Places autocomplete |
| `AVIATIONSTACK_API_KEY` | Optional | Flight lookup |

**Frontend build:**

| Define | Required |
|--------|----------|
| `API_BASE_URL` | Yes — `https://STAGING_DOMAIN` |

---

## P. Deploy order (quick reference)

1. Server packages (Node 22, nginx, mysql-client, PM2)
2. Clone/upload code → `/srv/ttaxi/current`
3. MySQL create DB + user
4. `backend/.env` (chmod 600)
5. `./database/migrate.sh`
6. `backend`: `npm ci --omit=dev` → PM2 start
7. Local: `flutter build web` → copy to `frontend/build/web`
8. nginx config → `nginx -t` → `reload`
9. `seed:mvp-demo` (optional)
10. `smoke:staging` + `rehearsal:mvp-e2e`
11. Manual UI checklist

---

## Q. Sign-off

| Step | Done | Date | Operator |
|------|------|------|----------|
| Health `/api/v1/health` | [ ] | | |
| Readiness OK | [ ] | | |
| smoke:staging pass | [ ] | | |
| rehearsal 19/19 | [ ] | | |
| Direct URLs work | [ ] | | |
| Manual E2E A–F | [ ] | | |

Notes:

_______________________________________________
