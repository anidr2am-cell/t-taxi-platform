# T-Ride Staging — Account Recovery & Password Reset

Operator guide for **Gabia T-Ride staging** when admin or driver login credentials are forgotten.

**Scope:** T-Ride only (`tride-*` stack at `/opt/t-ride`).  
**Out of scope:** Legacy KTaxi (`/opt/ktaxi`, `ktaxi-*`, host 80/443).

**Related:** [GABIA_STAGING_DEPLOY_LOG.md](./GABIA_STAGING_DEPLOY_LOG.md) · [MVP_DEV_SETUP.md](./MVP_DEV_SETUP.md) · [deploy/docker/README.md](../deploy/docker/README.md)

---

## 1. Staging URLs (current)

| Service | URL |
|---------|-----|
| Frontend (UI) | `http://103.60.127.213:3101/` |
| Backend API | `http://103.60.127.213:3100/` |
| Admin UI | `http://103.60.127.213:3101/admin` |
| Driver UI | `http://103.60.127.213:3101/driver` |

Legacy KTaxi remains on host **80/443** — do not modify.

---

## 2. Demo account identities (login identifiers only)

These are the **default MVP demo accounts** created by `seed:mvp-demo`. Passwords are **not** listed here — record them in your secure operator vault, or reset using the commands in §6–7.

| Role | Login field | Identifier |
|------|-------------|------------|
| Admin / Super Admin | Email | `admin@ttaxi.dev` |
| Driver | Phone | `+66810000001` |

Driver record also has email `driver@ttaxi.dev` (used by reset scripts, not the driver UI login field).

For local dev defaults, see [MVP_DEV_SETUP.md § Demo accounts](./MVP_DEV_SETUP.md) — treat staging passwords as **operator-managed** after first reset.

---

## 3. Before you reset — safety checklist

- [ ] Confirm you are on **T-Ride** (`tride-backend`), not KTaxi.
- [ ] Work only under `/opt/t-ride` and `deploy/docker/`.
- [ ] Do **not** stop/restart `ktaxi-*` containers.
- [ ] Do **not** delete `tride_mysql_data` or re-run clean migration.
- [ ] Do **not** print `.env`, JWT secrets, DB passwords, or `password_hash` values.
- [ ] Prefer **account-only** reset (`--skip-bookings` or targeted scripts) over full re-seed.

---

## 4. Available scripts (repo)

| Script | npm command | Purpose |
|--------|-------------|---------|
| `scripts/seed-mvp-demo.js` | `npm run seed:mvp-demo` | Upsert demo admin + driver + 6 scenario bookings |
| `scripts/createAdminUser.js` | `npm run create-admin-user` | Create or **reset** admin by email (`--force`) |
| `scripts/create-test-admin.js` | `npm run create-test-admin` | Upsert admin via `ADMIN_EMAIL` / `ADMIN_PASSWORD` env |
| `scripts/create-test-driver.js` | `npm run create-test-driver` | Create or **reset** driver by email (updates password if exists) |

**Helpers:** `scripts/mvpDemo/accounts.js` (`upsertDemoAdmin`, `upsertDemoDriver`) — used internally by seed; always passes `--force` for admin.

**Dedicated “password-only” script:** none. Use `create-admin-user --force` or `create-test-driver` instead.

---

## 5. `seed:mvp-demo` — what it does and re-run impact

### Creates / updates

| Step | Admin | Driver | Bookings |
|------|-------|--------|----------|
| Default run | Upsert `admin@ttaxi.dev` (password reset to demo default) | Upsert `+66810000001` (password reset to demo default) | **6 new** scenario bookings |
| `--skip-bookings` | Same upsert | Same upsert | **None** |
| `--skip-admin` | Uses existing row only | — | — |
| `--skip-driver` | — | Uses existing row only | — |

### Side effects on re-run

| Action | Effect |
|--------|--------|
| Admin upsert | Updates `password_hash`, role, profile; sets `is_active = 1` |
| Driver upsert | Updates `password_hash`, phone, driver row; sets `is_active = 1` |
| Bookings (default) | **Always creates new** booking numbers — does not delete old bookings |
| Production | **Blocked** when `NODE_ENV=production` |

### Recommended when credentials forgotten

```bash
# Safest for staging: reset demo accounts only, no new bookings
npm run seed:mvp-demo -- --skip-bookings
```

Use this when you want the **well-known demo passwords** from [MVP_DEV_SETUP.md](./MVP_DEV_SETUP.md). For a **custom** password, use §6 or §7 instead.

---

## 6. Admin password reset (T-Ride only)

### Option A — Reset demo admin to seed default (no new bookings)

On Gabia server:

```bash
cd /opt/t-ride/deploy/docker
docker compose -f docker-compose.staging.yml exec tride-backend \
  npm run seed:mvp-demo -- --skip-bookings
```

### Option B — Set a new custom password (recommended for staging)

```bash
cd /opt/t-ride/deploy/docker
docker compose -f docker-compose.staging.yml exec tride-backend \
  node scripts/createAdminUser.js \
    --email admin@ttaxi.dev \
    --password '<NEW_STRONG_PASSWORD>' \
    --name "MVP Admin" \
    --role SUPER_ADMIN \
    --force
```

Rules: password ≥ 8 chars, letters + numbers. Script prints email/role only — **never** prints hash.

### Option C — Different admin email

Same as Option B with `--email <other@example.com>`. Without `--force`, existing user returns an error.

### Verify login (no secrets in output)

```bash
curl -s -o /dev/null -w "%{http_code}\n" \
  -X POST http://103.60.127.213:3100/api/v1/auth/admin/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@ttaxi.dev","password":"<YOUR_PASSWORD>"}'
```

Expect `200` on success. Do not log the request body in shared terminals.

---

## 7. Driver password reset (T-Ride only)

Driver UI login uses **phone** `+66810000001` and password.

### Option A — Reset demo driver to seed default (no new bookings)

```bash
cd /opt/t-ride/deploy/docker
docker compose -f docker-compose.staging.yml exec tride-backend \
  npm run seed:mvp-demo -- --skip-bookings
```

### Option B — Set a new custom password (non-interactive in Docker)

```bash
cd /opt/t-ride/deploy/docker
docker compose -f docker-compose.staging.yml exec tride-backend \
  npm run create-test-driver -- \
    --email=driver@ttaxi.dev \
    --name="MVP Demo Driver" \
    --phone=+66810000001 \
    --password='<NEW_STRONG_PASSWORD>'
```

If the user already exists, script **updates** `password_hash` (no duplicate driver).

### Verify login

```bash
curl -s -o /dev/null -w "%{http_code}\n" \
  -X POST http://103.60.127.213:3100/api/v1/auth/driver/login \
  -H "Content-Type: application/json" \
  -d '{"phone":"+66810000001","password":"<YOUR_PASSWORD>"}'
```

Expect `200` on success.

---

## 8. Read-only checks (optional)

Confirm account rows exist **without** selecting `password_hash`:

```bash
cd /opt/t-ride/deploy/docker
docker compose -f docker-compose.staging.yml exec tride-backend \
  node -e "
    require('dotenv').config({ path: '/srv/tride/backend/.env' });
    const db = require('/srv/tride/backend/src/config/database');
    (async () => {
      const [admins] = await db.pool.query(
        \"SELECT id, email, role, is_active FROM users WHERE email = 'admin@ttaxi.dev' AND deleted_at IS NULL\"
      );
      const [drivers] = await db.pool.query(
        \"SELECT d.id, d.phone, u.email, d.is_active FROM drivers d JOIN users u ON u.id = d.user_id WHERE d.phone = '+66810000001' AND d.deleted_at IS NULL\"
      );
      console.log('admin:', admins[0] || 'missing');
      console.log('driver:', drivers[0] || 'missing');
      await db.pool.end();
    })();
  "
```

---

## 9. Commands you must never run (T-Ride account recovery context)

| Forbidden | Reason |
|-----------|--------|
| `docker stop/restart/rm ktaxi-*` | Breaks legacy production |
| `docker restart ktaxi-nginx` | Affects 80/443 for all sites |
| Edit `/opt/ktaxi/**` | Legacy stack |
| `docker volume rm tride_mysql_data` | Wipes all T-Ride staging data |
| `docker compose down -v` (T-Ride) | Removes DB volume |
| `./database/migrate.sh` on running populated DB without ops approval | Risk of partial apply |
| `SELECT password_hash ...` / logging hashes | Secret leakage |
| `cat deploy/docker/.env` in shared chat | Contains DB/JWT secrets |
| Full `seed:mvp-demo` when only password forgotten | Creates 6 **extra** demo bookings |

---

## 10. Secret handling principles

- Store staging passwords in a **password manager** or secure ops vault — not in Git, not in chat.
- Reset scripts write `password_hash` only inside `tride_staging` — never echo hash or plaintext password to logs.
- After reset, test via browser or curl status code — do not paste tokens into tickets.
- If demo defaults were used in a **public** staging URL, rotate to custom passwords via §6B / §7B.

---

## 11. Quick decision tree

```
Forgot admin password?
  ├─ OK with demo default? → seed:mvp-demo --skip-bookings
  └─ Need custom password? → createAdminUser.js --force

Forgot driver password?
  ├─ OK with demo default? → seed:mvp-demo --skip-bookings
  └─ Need custom password? → create-test-driver --password=...

Also need fresh demo bookings? → full seed:mvp-demo (adds 6 bookings)

Account missing entirely? → seed:mvp-demo --skip-bookings (creates if absent)
```

---

## 12. KTaxi impact

All commands above run **inside `tride-backend`** against **`tride_staging`** only. No KTaxi containers, volumes, networks, or nginx configs are read or modified.

---

## Sign-off

| Action | Date | Operator |
|--------|------|----------|
| Admin reset verified (`/admin` login) | | |
| Driver reset verified (`/driver` login) | | |
| KTaxi `88taxi.net` still OK | | |

Notes:

_______________________________________________
