# MVP Dev Setup

Developer reference for the **manual dispatch + guest lookup** MVP.

> **New to the project?** Start with **[MVP_DEMO_GUIDE.md](./MVP_DEMO_GUIDE.md)** — step-by-step setup a third party can follow without reading the codebase.

---

## Execution order (local demo)

```powershell
# Step 1 — DB migrate + demo seed
cd C:\TTaxi\database
.\setup-mvp-demo.ps1

# Step 2 — Backend
cd C:\TTaxi\backend
copy .env.example .env    # set DB_* and JWT_* — see MVP_DEMO_GUIDE §2.2
npm install
npm start                 # http://localhost:3000

# Step 3 — Frontend (dev)
cd C:\TTaxi\frontend
flutter pub get
flutter run -d chrome --web-port=8080

# Step 4 — Automated checks
cd C:\TTaxi\backend
npm test
npm run rehearsal:mvp-e2e

cd C:\TTaxi\frontend
flutter test
flutter build web
```

---

## Environment variables

Full template: `backend/.env.example`

**Local demo minimum:**

```env
NODE_ENV=development
PORT=3000
DB_HOST=127.0.0.1
DB_PORT=3306
DB_NAME=ttaxi
DB_USER=root
DB_PASSWORD=your-password
JWT_ACCESS_SECRET=replace-with-random-string-at-least-32-chars
JWT_REFRESH_SECRET=replace-with-another-random-string-32-chars
CORS_ORIGIN=http://localhost:8080
```

Optional: `GOOGLE_MAPS_API_KEY`, `AVIATIONSTACK_API_KEY` (wizard Places/flight features).

Production/staging: use all sections in `.env.example`; never commit real `.env`.

---

## Direct URLs (path routing)

| Screen | URL |
|--------|-----|
| Landing | http://localhost:8080/ |
| Guest lookup | http://localhost:8080/booking/lookup |
| Admin dispatch | http://localhost:8080/admin |
| Driver login | http://localhost:8080/driver |

Requires `usePathUrlStrategy()` in `frontend/lib/main.dart` (included since Phase 9).

---

## Demo accounts (dev/staging only)

| Role | Login | Password |
|------|-------|----------|
| Super Admin | `admin@ttaxi.dev` (email) | `Admin123456!` |
| Driver | `+66810000001` (phone) | `Driver123456!` |

Admin: `/admin` opens **Reservations/Dispatch** tab. Driver: phone + password.

---

## Seed & rehearsal scripts

```powershell
cd C:\TTaxi\backend

# Default: admin + driver + 6 status bookings
npm run seed:mvp-demo

# Subset
node scripts/seed-mvp-demo.js --scenarios=PENDING,COMPLETED,CANCELLED

# Accounts only
node scripts/seed-mvp-demo.js --skip-bookings

# API E2E (after seed)
npm run rehearsal:mvp-e2e
```

### Seeded guest phones (booking numbers vary each run)

| Status | Phone |
|--------|-------|
| PENDING | `+66820000001` |
| DRIVER_ASSIGNED | `+66820000002` |
| ON_ROUTE | `+66820000003` |
| DRIVER_ARRIVED | `+66820000004` |
| COMPLETED | `+66820000005` |
| CANCELLED | `+66820000006` |

---

## Database

```powershell
cd C:\TTaxi\database
.\migrate.ps1          # migrations only
.\setup-mvp-demo.ps1   # migrate + seed
.\smoke-test.ps1       # optional idempotency check
```

Migrations seed service types, vehicle types, BKK→Pattaya pricing, etc. No extra SQL needed for MVP if `migrate.ps1` succeeds.

---

## Production web build

```powershell
cd C:\TTaxi\frontend
flutter build web --release --dart-define=API_BASE_URL=https://api.your-domain.com
```

Deploy `frontend/build/web/` with SPA fallback to `index.html`. See [MVP_DEMO_GUIDE.md §7](./MVP_DEMO_GUIDE.md).

---

## Final test commands

| Command | Location | Expected |
|---------|----------|----------|
| `npm test` | `backend/` | 428 pass |
| `flutter test` | `frontend/` | 250 pass |
| `npm run rehearsal:mvp-e2e` | `backend/` | 19/19 pass |
| `flutter build web` | `frontend/` | `build/web` created |

---

## MVP scope (out of bounds)

Payment, customer signup, chat, QR, Socket.IO live sync, auto-dispatch, driver GPS map.

Details: [MVP_DEMO_GUIDE.md §8](./MVP_DEMO_GUIDE.md)

---

## Related

- [MVP_DEMO_GUIDE.md](./MVP_DEMO_GUIDE.md) — operator-facing setup
- [MVP_MANUAL_E2E_CHECKLIST.md](./MVP_MANUAL_E2E_CHECKLIST.md) — manual sign-off
