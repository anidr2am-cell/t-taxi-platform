# MVP Demo Guide (Phase 10)

Run the **T-Ride MVP demo** from a clean checkout. Intended for operators, QA, or staging deployers who may not know the codebase.

**Flow:** guest booking → admin assign driver → driver trip statuses → guest lookup refresh.

---

## 1. Prerequisites

| Tool | Version |
|------|---------|
| MySQL | 8.x |
| Node.js | 22+ |
| Flutter SDK | 3.x (with `flutter` on PATH) |
| PowerShell | 5+ (Windows) or adapt commands for bash |

---

## 2. One-time setup

### 2.1 Clone and install

```powershell
cd C:\TTaxi\backend
npm install

cd C:\TTaxi\frontend
flutter pub get
```

### 2.2 Backend environment

```powershell
cd C:\TTaxi\backend
copy .env.example .env
```

Edit `backend/.env` — **minimum for local demo:**

| Variable | Example (local) | Required |
|----------|-----------------|----------|
| `NODE_ENV` | `development` | Yes |
| `PORT` | `3000` | Yes |
| `DB_HOST` | `127.0.0.1` | Yes |
| `DB_PORT` | `3306` | Yes |
| `DB_NAME` | `ttaxi` | Yes |
| `DB_USER` | your MySQL user | Yes |
| `DB_PASSWORD` | your MySQL password | Yes |
| `JWT_ACCESS_SECRET` | random string ≥ 32 chars | Yes |
| `JWT_REFRESH_SECRET` | random string ≥ 32 chars | Yes |
| `CORS_ORIGIN` | `http://localhost:8080` | Yes |
| `GOOGLE_MAPS_API_KEY` | — | Optional (Places search) |
| `AVIATIONSTACK_API_KEY` | — | Optional (flight lookup) |

> Staging/production: use `backend/.env.example` as the full template. Set `NODE_ENV=production`, strong secrets, and real `CORS_ORIGIN` / `PUBLIC_API_URL`.

### 2.3 Database migrate + demo seed

```powershell
cd C:\TTaxi\database
.\setup-mvp-demo.ps1
```

This runs migrations and `npm run seed:mvp-demo` (admin, driver, 6 status-scenario bookings).

**Save the seed output** — booking numbers change each run.

---

## 3. Start services

### Terminal A — Backend

```powershell
cd C:\TTaxi\backend
npm start
```

Health: http://localhost:3000/api/v1/health → `"status":"ok"`

### Terminal B — Frontend (development)

```powershell
cd C:\TTaxi\frontend
flutter run -d chrome --web-port=8080
```

### Direct URLs

| Screen | URL |
|--------|-----|
| Landing | http://localhost:8080/ |
| Guest lookup | http://localhost:8080/booking/lookup |
| Admin dispatch | http://localhost:8080/admin |
| Driver login | http://localhost:8080/driver |

---

## 4. Demo accounts

| Role | Login field | Value | Password |
|------|-------------|-------|----------|
| Admin | Email | `admin@ttaxi.dev` | `Admin123456!` |
| Driver | Phone | `+66810000001` | `Driver123456!` |

Guest lookup uses **bookingNumber + phone** from seed output (phones `+66820000001` … `+66820000006`).

---

## 5. Demo script (15–20 min)

1. **Customer** — Landing → Book now → Airport Pickup BKK → Pattaya → submit → note booking number.
2. **Admin** — `/admin` → login → find PENDING booking → Assign → MVP Demo Driver.
3. **Driver** — `/driver` → login → Jobs → Start route → Mark arrived → Complete trip.
4. **Customer** — `/booking/lookup` → enter number + phone → Refresh → see Completed.

Optional: lookup each seeded status (`PENDING` … `CANCELLED`) using phones above.

Full step list: [MVP_MANUAL_E2E_CHECKLIST.md](./MVP_MANUAL_E2E_CHECKLIST.md)

---

## 6. Automated verification

Run with backend up and DB seeded:

```powershell
cd C:\TTaxi\backend
npm test
npm run seed:mvp-demo
npm run rehearsal:mvp-e2e

cd C:\TTaxi\frontend
flutter test
```

Expected (2026-07-04 baseline):

- Backend: **428** tests pass
- Frontend: **250** tests pass
- Rehearsal: **19/19** checks pass

---

## 7. Production / staging web build

> **Deploying to a test server?** Follow [MVP_DEPLOYMENT_PREP.md](./MVP_DEPLOYMENT_PREP.md) for nginx, PM2, CORS, env, and smoke tests.

### Build frontend

Point the built app at your API host:

```powershell
cd C:\TTaxi\frontend
flutter build web --release `
  --dart-define=API_BASE_URL=https://api.your-domain.com
```

Output: `frontend/build/web/`

### Serve static files (SPA)

Path URLs (`/booking/lookup`, `/admin`, `/driver`) require **fallback to `index.html`**. Examples:

- **nginx:** `try_files $uri $uri/ /index.html;`
- **Express static:** use a catch-all route after static middleware
- **Flutter dev server:** handles this automatically

### Backend

```powershell
cd C:\TTaxi\backend
set NODE_ENV=production
npm start
```

Ensure `CORS_ORIGIN` matches the frontend origin. Run migrations on the target DB; run `seed:mvp-demo` **only** on isolated demo/staging DBs (blocked when `NODE_ENV=production`).

---

## 8. Known limitations (MVP)

| Area | Status |
|------|--------|
| Payment | Not implemented — bookings show pay-driver summary only |
| Customer signup | Not required — guest booking + lookup only |
| Chat | Hidden in MVP customer UI; not part of demo flow |
| QR boarding/completion | Hidden in MVP customer/driver UI |
| Real-time sync | No Socket.IO push to guest — use **Refresh** on lookup |
| Auto-dispatch | Admin manual assign only |
| Driver live map | Not in MVP demo |
| Rate limit | Guest lookup: 10 req/min per IP in production, 30 in dev |

---

## 9. Troubleshooting

| Symptom | Check |
|---------|--------|
| API connection refused | `npm start` running? Port 3000 free? |
| DB access denied | `backend/.env` DB_* values; MySQL running |
| Seed fails in production | `seed:mvp-demo` refuses `NODE_ENV=production` |
| Lookup 429 | Wait 1 min or use dev `NODE_ENV=development` |
| `/booking/lookup` shows landing | Rebuild frontend (path URL strategy in `main.dart`) |
| Flutter port 8080 in use | Stop old `flutter run` or use `--web-port=8081` |
| Empty driver detail after complete | Fixed Phase 9 — pull latest and rebuild |

---

## 10. Related docs

- [MVP_DEPLOYMENT_PREP.md](./MVP_DEPLOYMENT_PREP.md) — **staging/test server deploy** (Gabia, nginx, PM2, CORS, env)
- [MVP_DEV_SETUP.md](./MVP_DEV_SETUP.md) — script options, migration notes
- [MVP_MANUAL_E2E_CHECKLIST.md](./MVP_MANUAL_E2E_CHECKLIST.md) — sign-off checklist
- [openapi/README.md](./openapi/README.md) — API reference
