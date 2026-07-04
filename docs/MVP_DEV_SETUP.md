# MVP Dev Setup (Phase 6)

Local/staging guide for running the **manual dispatch + guest status lookup** MVP flow.

> Dev-only credentials below. Never use in production.

## Prerequisites

- MySQL 8.x
- Node.js 22+
- Flutter SDK (frontend)
- `backend/.env` configured (copy from `backend/.env.example`)

## 1. Database migration

From repo root (Windows):

```powershell
cd C:\TTaxi\database
.\migrate.ps1
```

Optional idempotency smoke test:

```powershell
.\smoke-test.ps1
```

### What migrations already seed

| Data | Source | Notes |
|------|--------|-------|
| Service types | `11_seed.sql` | AIRPORT_PICKUP, AIRPORT_DROPOFF, CITY_TRANSFER, GOLF_TRANSFER |
| Vehicle types | `11_seed.sql` | SEDAN, SUV, VAN, … |
| Airports | `11_seed.sql` | BKK, DMK, CNX, HKT |
| Route BKK → Pattaya | `15_pricing_architecture.sql` | AIRPORT_PICKUP + SUV/VAN prices |
| Charge policies | `15_pricing_architecture.sql` | NAME_SIGN, NIGHT, AIRPORT surcharges |
| Settlement defaults | `17_settlement_settings_seed.sql` | Commission rate |

No extra migration is required for MVP E2E if `migrate.ps1` completes successfully.

## 2. Backend

```powershell
cd C:\TTaxi\backend
npm install
npm start
```

Health check: `GET http://localhost:3000/api/v1/health`

## 3. MVP demo accounts + bookings (one command)

```powershell
cd C:\TTaxi\backend
npm run seed:mvp-demo
```

Or full setup (migrate + seed):

```powershell
cd C:\TTaxi\database
.\setup-mvp-demo.ps1
```

### Default test accounts

| Role | Login | Password |
|------|-------|----------|
| Super Admin | `admin@ttaxi.dev` (email) | `Admin123456!` |
| Driver | `+66810000001` (phone) | `Driver123456!` |

Admin login: Admin app → **Dispatch** tab → email + password.

Driver login: Driver app → phone + password.

### Seed script options

```powershell
# All 6 status scenarios (default)
node scripts/seed-mvp-demo.js

# Subset only
node scripts/seed-mvp-demo.js --scenarios=PENDING,COMPLETED,CANCELLED

# Accounts only (no bookings)
node scripts/seed-mvp-demo.js --skip-bookings
```

### Seeded booking scenarios

After `seed:mvp-demo`, the script prints a table like:

| Status | Guest phone pattern |
|--------|---------------------|
| PENDING | `+66820000001` |
| DRIVER_ASSIGNED | `+66820000002` |
| ON_ROUTE | `+66820000003` |
| DRIVER_ARRIVED | `+66820000004` |
| COMPLETED | `+66820000005` |
| CANCELLED | `+66820000006` |

Use **bookingNumber + phone** on the guest lookup screen (`/booking/lookup`).

## 4. Manual account scripts (alternative)

```powershell
# Admin / Super Admin
npm run create-admin-user -- --email admin@ttaxi.dev --password "Admin123456!" --name "MVP Admin" --role SUPER_ADMIN --force

# Driver (email stored; login uses phone)
npm run create-test-driver -- --email=driver@ttaxi.dev --name="MVP Demo Driver" --phone=+66810000001 --password=Driver123456!
```

## 5. Frontend

```powershell
cd C:\TTaxi\frontend
flutter pub get
flutter run -d chrome --web-port=8080
```

Guest lookup route: `/booking/lookup`

## 6. Create a fresh test booking (UI)

1. Landing → **Book now**
2. Service: **Airport Pickup**
3. Origin: **BKK**, Destination: **Pattaya**
4. Pickup time: at least **2 hours** ahead
5. Customer phone: any valid number (used for lookup)
6. Complete booking → copy **bookingNumber** → **Track my booking**

## 7. Automated tests

```powershell
cd C:\TTaxi\backend
npm test

cd C:\TTaxi\frontend
flutter test
```

### API-level E2E rehearsal (Phase 8)

After seeding, run the automated MVP flow rehearsal (creates one fresh booking + verifies all 6 seeded statuses via HTTP):

```powershell
cd C:\TTaxi\backend
npm run seed:mvp-demo
npm run rehearsal:mvp-e2e
```

Requires migrated DB and demo accounts. Does not replace manual UI walkthrough in the checklist, but validates booking → assign → driver trip → guest lookup end-to-end.

## Out of scope (Phase 6)

Payment, Socket.IO live sync, chat, QR boarding/completion, auto-dispatch, driver GPS tracking, customer signup.

See also: [MVP_MANUAL_E2E_CHECKLIST.md](./MVP_MANUAL_E2E_CHECKLIST.md)

## 8. Pre-demo polish checklist (Phase 7)

Before a live demo, quickly verify:

1. `flutter test` and `npm test` pass
2. Guest complete/lookup pages show **no QR or chat** without explicit dev flags
3. Admin dispatch: empty/error/retry states render correctly
4. Driver completes trip and can still open read-only detail (no post-action 404)
5. Run section **H** in [MVP_MANUAL_E2E_CHECKLIST.md](./MVP_MANUAL_E2E_CHECKLIST.md)
