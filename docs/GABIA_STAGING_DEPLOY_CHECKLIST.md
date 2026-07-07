# Gabia Staging Deploy Checklist — T-Ride (tride-staging)

Operator runbook to deploy **T-Ride MVP** on the **same Gabia VPS** as the existing **KTaxi/TTaxi** stack **without interrupting production**.

> **Never** paste real passwords, JWT secrets, or API keys into Git, docs, or chat.

**Architecture doc:** [MVP_DEPLOYMENT_PREP.md](./MVP_DEPLOYMENT_PREP.md)  
**Local demo:** [MVP_DEMO_GUIDE.md](./MVP_DEMO_GUIDE.md) · **E2E sign-off:** [MVP_MANUAL_E2E_CHECKLIST.md](./MVP_MANUAL_E2E_CHECKLIST.md)

---

## 0. Two projects on one server — do not confuse

| | **Existing KTaxi / TTaxi (DO NOT TOUCH)** | **New T-Ride MVP (this deploy)** |
|---|-------------------------------------------|----------------------------------|
| Product | Legacy TTaxi/KTaxi web | T-Ride MVP (this repo) |
| Server path | `/opt/ktaxi` | **`/opt/t-ride`** |
| Orchestration | `/opt/ktaxi/infra/docker-compose.yml` | **`/opt/t-ride/deploy/docker/docker-compose.staging.yml`** |
| Container prefix | `ktaxi-*` | **`tride-*`** |
| Docker network | `infra_ktaxi-net` (ktaxi internal) | **`tride-net`** |
| Database | **Postgres** (`ktaxi-postgres`) | **MariaDB 10.11** (`tride-db`) — **separate** |
| DB name | (ktaxi Postgres DBs) | **`tride_staging`** |
| Edge / TLS | **`ktaxi-nginx`** → host **80/443** | **No host 80/443** in Phase 1–3 |
| Domains | `88taxi.net`, `driver.88taxi.net`, `admin.88taxi.net`, `api.88taxi.net`, `ws.88taxi.net` | **`tride-staging.88taxi.net`** (Phase 4+) |
| Internal ports (reference) | api **8787**, realtime **8788** | backend host **3100**→3000, frontend host **3101**→80 |

### Absolute prohibitions

- Do **not** modify `/opt/ktaxi` or `/opt/ktaxi/infra/docker-compose.yml`
- Do **not** stop, restart, or delete **`ktaxi-*`** containers
- Do **not** add T-Ride services to the ktaxi compose file
- Do **not** install **host** nginx or bind host **80/443**
- Do **not** install host Node.js, npm, or PM2 for T-Ride (use Docker)
- Do **not** run T-Ride migrations against **`ktaxi-postgres`**
- Do **not** edit existing **`88taxi.net`** server blocks until Phase 4 review

---

## 1. T-Ride naming rules (mandatory)

| Item | Value |
|------|-------|
| Deploy name | `tride-staging` |
| Server root | `/opt/t-ride` |
| Compose project | `tride-staging` |
| Compose file | `/opt/t-ride/deploy/docker/docker-compose.staging.yml` |
| Env file | `/opt/t-ride/deploy/docker/.env` |
| Docker network | `tride-net` |
| DB container | `tride-db` |
| DB name | `tride_staging` |
| DB user (example) | `tride_app` |
| Backend container | `tride-backend` |
| Frontend container | `tride-frontend` |
| Uploads (host volume) | `/opt/t-ride/uploads` |
| Staging domain (target) | `tride-staging.88taxi.net` |
| Temp host port — API | **`3100`** → `tride-backend:3000` |
| Temp host port — web | **`3101`** → `tride-frontend:80` |

Local repo path `C:\TTaxi` is **source code only** — on the server always use **`/opt/t-ride`**.

---

## 2. Deployment phases (recommended order)

```
Phase 1  Docker Compose at /opt/t-ride (tride-db + tride-backend + tride-frontend)
Phase 2  Smoke on host :3100 / :3101 — no 80/443, no ktaxi changes
Phase 3  Migration + seed:mvp-demo + rehearsal:mvp-e2e on tride_staging
Phase 4  Plan tride-staging.88taxi.net → ktaxi-nginx upstream (review only)
Phase 5  Apply ktaxi-nginx change (last, with rollback plan)
```

---

## 3. Work split — local vs server

| Where | Tasks |
|-------|--------|
| **Local (`C:\TTaxi`)** | `npm test`, `flutter test`, `flutter build web`, commit/push, build Docker images (optional CI) |
| **Gabia VPS** | `git clone` → `/opt/t-ride`, `deploy/docker/.env`, `docker compose -f deploy/docker/docker-compose.staging.yml up`, migrate, seed, port smoke |
| **Phase 4–5 only** | DNS + **ktaxi-nginx** vhost for `tride-staging.88taxi.net` |

---

## 4. Phase 1 — Prepare `/opt/t-ride` (Docker only)

### 4.1 Prerequisites on server

```bash
docker --version
docker compose version
# Confirm ktaxi is running — do not restart it
docker ps --format 'table {{.Names}}\t{{.Ports}}' | grep ktaxi
```

**Do not install:** host nginx, PM2, Node.js (unless needed for local admin tasks unrelated to T-Ride runtime).

### 4.2 Directory layout

```bash
sudo mkdir -p /opt/t-ride/uploads
sudo chown -R "$USER":"$USER" /opt/t-ride
cd /opt/t-ride

git clone https://github.com/anidr2am-cell/t-taxi-platform.git .
# or rsync/scp release tarball — never into /opt/ktaxi
```

Expected tree:

```text
/opt/t-ride/
  backend/
  frontend/
  database/
  deploy/
    docker/
      docker-compose.staging.yml
      Dockerfile.backend
      Dockerfile.frontend
      .env.example          # copy to .env on server (chmod 600)
  uploads/                    # optional bind-mount override (see deploy/docker/README.md)
```

**Compose quick reference:** [deploy/docker/README.md](../deploy/docker/README.md)

### 4.3 Compose services (repo)

| Service | Container name | Image / build | Notes |
|---------|----------------|---------------|-------|
| `tride-db` | `tride-db` | `mariadb:10.11` | DB `tride_staging`; volume `tride_mysql_data` |
| `tride-backend` | `tride-backend` | `deploy/docker/Dockerfile.backend` | Node 22, host **3100**→3000 |
| `tride-frontend` | `tride-frontend` | `deploy/docker/Dockerfile.frontend` | nginx, host **3101**→80 |

Network: **`tride-net`** only. Do **not** attach to `infra_ktaxi-net` in this phase.

### 4.4 Server `.env` (placeholders only — edit on server)

```bash
cd /opt/t-ride/deploy/docker
cp .env.example .env
chmod 600 .env
# edit .env — replace SERVER_IP and all REPLACE_* secrets
```

Template: `deploy/docker/.env.example`. Key values for **split-port smoke**:

```env
MYSQL_ROOT_PASSWORD=REPLACE_WITH_STRONG_ROOT_PASSWORD
DB_NAME=tride_staging
DB_USER=tride_app
DB_PASSWORD=REPLACE_WITH_STRONG_PASSWORD

JWT_ACCESS_SECRET=REPLACE_WITH_RANDOM_32_PLUS_CHARS
JWT_REFRESH_SECRET=REPLACE_WITH_RANDOM_32_PLUS_CHARS

CORS_ORIGIN=http://SERVER_IP:3101
PUBLIC_API_URL=http://SERVER_IP:3100
TRIDE_API_BASE_URL=http://SERVER_IP:3100

TRIDE_BACKEND_HOST_PORT=3100
TRIDE_FRONTEND_HOST_PORT=3101
```

Phase 5+ (public domain — future ktaxi-nginx step):

```env
CORS_ORIGIN=https://tride-staging.88taxi.net
PUBLIC_API_URL=https://tride-staging.88taxi.net
TRIDE_API_BASE_URL=https://tride-staging.88taxi.net
```

Generate secrets on server: `openssl rand -base64 48`

---

## 5. Phase 2 — Temp port smoke (no 80/443)

Publish T-Ride to **host ports that do not conflict with ktaxi-nginx**:

| Host port | Maps to | Purpose |
|-----------|---------|---------|
| **3100** | `tride-backend:3000` | REST API / health (direct) |
| **3101** | `tride-frontend:80` | Flutter SPA (UI smoke) |

```bash
cd /opt/t-ride/deploy/docker
docker compose -f docker-compose.staging.yml up -d --build
docker compose -f docker-compose.staging.yml ps
```

Smoke from your workstation (replace `SERVER_IP`):

```bash
curl -s http://SERVER_IP:3100/api/v1/health
curl -s http://SERVER_IP:3100/api/v1/health/readiness
curl -s -o /dev/null -w "%{http_code}" http://SERVER_IP:3101/
curl -s -o /dev/null -w "%{http_code}" http://SERVER_IP:3101/booking/lookup
curl -s -o /dev/null -w "%{http_code}" http://SERVER_IP:3101/admin
curl -s -o /dev/null -w "%{http_code}" http://SERVER_IP:3101/driver
```

Browser (Phase 2):

- `http://SERVER_IP:3101/`
- `http://SERVER_IP:3101/booking/lookup`
- `http://SERVER_IP:3101/admin`
- `http://SERVER_IP:3101/driver`

**Frontend image build** uses `TRIDE_API_BASE_URL` from `deploy/docker/.env` (API on **:3100**). Rebuild after changing:

```bash
docker compose -f docker-compose.staging.yml up -d --build tride-frontend
```

After Phase 5 (HTTPS domain), update `.env` and rebuild frontend with `TRIDE_API_BASE_URL=https://tride-staging.88taxi.net`.

---

## 6. Phase 3 — Migration, seed, automated tests

Run **inside** `tride-backend` container (or one-off migrate job) — **never** against ktaxi-postgres.

### 6.1 MariaDB bootstrap

Compose creates `tride_staging` and `tride_app` from `deploy/docker/.env` on first `tride-db` start (`mariadb:10.11`). Manual SQL is only needed if the volume already exists with different credentials.

**If `tride-db` previously used `mysql:8.4` or migration failed:** stop the stack, remove **only** `tride_mysql_data`, then `up` again. **Never** delete ktaxi / `infra_*` volumes.

```bash
cd /opt/t-ride/deploy/docker
docker compose -f docker-compose.staging.yml down
docker volume rm tride_mysql_data
docker compose -f docker-compose.staging.yml up -d --build
```

### 6.2 Migrations

```bash
cd /opt/t-ride/deploy/docker
docker compose -f docker-compose.staging.yml exec tride-backend \
  sh -c 'cd /srv/tride/database && ./migrate.sh'
```

Verify:

```bash
docker compose -f docker-compose.staging.yml exec tride-db \
  mysql -u tride_app -p tride_staging -e "SHOW TABLES LIKE 'bookings';"
```

### 6.3 Demo seed (tride_staging only)

```bash
docker compose -f docker-compose.staging.yml exec tride-backend npm run seed:mvp-demo
```

Demo accounts (change if staging is public):

| Role | Login | Default password |
|------|-------|------------------|
| Admin | `admin@ttaxi.dev` | `Admin123456!` |
| Driver | `+66810000001` | `Driver123456!` |

### 6.4 Rehearsal (from dev machine or exec into backend)

```bash
docker compose -f docker-compose.staging.yml exec tride-backend npm run rehearsal:mvp-e2e
# expect 19/19 pass
```

Port-based smoke (Phase 2 — API direct + UI):

```bash
export STAGING_BASE_URL=http://SERVER_IP:3100
export STAGING_FRONTEND_URL=http://SERVER_IP:3101
npm run smoke:staging
```

---

## 7. Phase 4 — Plan public domain (review before any ktaxi change)

**Target:** `https://tride-staging.88taxi.net` → T-Ride stack **without** stopping ktaxi-nginx.

### 7.1 DNS

Add **A/AAAA** record: `tride-staging.88taxi.net` → same server IP as `88taxi.net`.

### 7.2 Routing model (recommended)

Keep T-Ride on **host port 3101** (frontend). Add a **new** server block in **ktaxi-nginx** (Phase 5 only):

```nginx
# PLANNED — do not apply until Phase 5 sign-off
# New server block ONLY for tride-staging.88taxi.net
# Do NOT modify 88taxi.net / admin / driver / api / ws blocks

upstream tride_staging_web {
    server host.docker.internal:3101;
    # or: server 172.17.0.1:3101;  # Docker bridge to host — verify on server
}

server {
    listen 443 ssl http2;
    server_name tride-staging.88taxi.net;
    # reuse existing wildcard cert or issue cert for subdomain

    location / {
        proxy_pass http://tride_staging_web;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

T-Ride **frontend nginx** handles SPA fallback and optional `/api/` proxy — ktaxi-nginx proxies to **:3101** (frontend).

### 7.3 Pre-change checklist (Phase 4 review)

- [ ] Document current `ktaxi-nginx` config (backup)
- [ ] Confirm port **3101** reachable from inside `ktaxi-nginx` container
- [ ] Confirm **no** port 80/443 binding outside ktaxi stack
- [ ] Update T-Ride `CORS_ORIGIN` + rebuild frontend for `https://tride-staging.88taxi.net`
- [ ] Rollback plan: remove new server block only; `docker compose down` for T-Ride does **not** affect ktaxi

---

## 8. Phase 5 — Apply ktaxi-nginx change (last step)

1. Backup ktaxi nginx config volume / file
2. Add **only** `tride-staging.88taxi.net` server block
3. `docker exec ktaxi-nginx nginx -t`
4. Reload **ktaxi-nginx** container only (not host nginx)
5. Verify:

| URL | Expected |
|-----|----------|
| `https://tride-staging.88taxi.net/` | T-Ride landing |
| `https://tride-staging.88taxi.net/booking/lookup` | Guest lookup |
| `https://tride-staging.88taxi.net/admin` | Admin dispatch |
| `https://tride-staging.88taxi.net/driver` | Driver login |
| `https://88taxi.net/` | **Unchanged** — existing KTaxi |

If anything breaks on **88taxi.net**, **revert ktaxi-nginx** immediately — do not debug by stopping T-Ride first.

---

## 9. Operator manual verification

Use [MVP_MANUAL_E2E_CHECKLIST.md](./MVP_MANUAL_E2E_CHECKLIST.md) sections **A–F** against:

- Phase 2 UI: `http://SERVER_IP:3101` (API health: `:3100`)
- Phase 5: `https://tride-staging.88taxi.net`

---

## 10. Logs & rollback

### T-Ride only

```bash
cd /opt/t-ride/deploy/docker
docker compose -f docker-compose.staging.yml logs -f tride-backend
docker compose -f docker-compose.staging.yml logs -f tride-frontend
docker compose -f docker-compose.staging.yml logs -f tride-db
docker compose -f docker-compose.staging.yml down
docker compose -f docker-compose.staging.yml up -d --build
```

### KTaxi (troubleshooting reference only — do not run unless ops owns KTaxi)

```bash
docker logs ktaxi-nginx --tail 100
docker logs ktaxi-api --tail 100
```

### Rollback summary

| Scope | Action |
|-------|--------|
| T-Ride bad deploy | `docker compose down`; fix `/opt/t-ride`; `up -d` again |
| ktaxi-nginx bad vhost | Restore backed-up config; reload **ktaxi-nginx** only |
| Never | `docker stop ktaxi-*` as T-Ride rollback step |

---

## 11. Required environment variables (T-Ride)

| Variable | Example (Docker) |
|----------|------------------|
| `NODE_ENV` | `staging` |
| `DB_HOST` | `tride-db` |
| `DB_NAME` | `tride_staging` |
| `DB_USER` / `DB_PASSWORD` | `tride_app` / (secret) |
| `JWT_*_SECRET` | strong random |
| `CORS_ORIGIN` | `http://SERVER_IP:3101` or `https://tride-staging.88taxi.net` |
| `PUBLIC_API_URL` | `http://SERVER_IP:3100` or public HTTPS URL |
| `UPLOAD_DIR` | `/srv/tride/uploads` (volume `tride_uploads`) |
| `TRIDE_API_BASE_URL` | Flutter build arg in `deploy/docker/.env` |

**Flutter (Docker build):** `TRIDE_API_BASE_URL` — split smoke uses **`http://SERVER_IP:3100`**; same-origin domain phase uses **`https://tride-staging.88taxi.net`**

---

## 12. Sign-off

| Phase | Done | Date | Operator |
|-------|------|------|----------|
| 1 — compose at `/opt/t-ride` | [ ] | | |
| 2 — `:3100` API + `:3101` UI smoke | [ ] | | |
| 3 — migrate + seed + rehearsal | [ ] | | |
| 4 — ktaxi-nginx plan reviewed | [ ] | | |
| 5 — `tride-staging.88taxi.net` live | [ ] | | |
| KTaxi `88taxi.net` still OK | [ ] | | |
| Manual E2E A–F | [ ] | | |

Notes:

_______________________________________________
