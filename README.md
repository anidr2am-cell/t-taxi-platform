# T-Ride (TTaxi) — Thailand Airport Transfer Platform

MVP scope: **guest booking → admin manual dispatch → driver trip flow → guest status lookup**.

## Quick links

| Document | Purpose |
|----------|---------|
| **[docs/MVP_DEMO_GUIDE.md](docs/MVP_DEMO_GUIDE.md)** | Start here — full demo/test setup for a new operator |
| **[docs/GABIA_STAGING_DEPLOY_CHECKLIST.md](docs/GABIA_STAGING_DEPLOY_CHECKLIST.md)** | **Gabia — T-Ride `tride-staging` at `/opt/t-ride` (coexist with `/opt/ktaxi`)** |
| **[deploy/docker/README.md](deploy/docker/README.md)** | **Docker Compose staging — `3100` API / `3101` UI** |
| **[docs/MVP_DEPLOYMENT_PREP.md](docs/MVP_DEPLOYMENT_PREP.md)** | Staging architecture, Docker/`tride-*` naming, CORS, env, smoke tests |
| [docs/MVP_DEV_SETUP.md](docs/MVP_DEV_SETUP.md) | Developer reference (accounts, scripts, URLs) |
| [docs/MVP_MANUAL_E2E_CHECKLIST.md](docs/MVP_MANUAL_E2E_CHECKLIST.md) | Manual verification checklist |
| **[docs/STAGING_ACCOUNT_RESET.md](docs/STAGING_ACCOUNT_RESET.md)** | **Gabia staging — admin/driver password reset (T-Ride only)** |

## Tech stack

| Layer | Technology |
|-------|------------|
| Frontend | Flutter Web (PWA) |
| Backend | Node.js 22+ / Express |
| Database | MySQL 8.x |

## Project structure

```
TTaxi/
├── backend/     # REST API
├── frontend/    # Flutter Web
├── database/    # Migrations & seeds
└── docs/        # MVP guides & OpenAPI
```

## Minimum commands (local demo)

```powershell
# 1. Database + demo data
cd C:\TTaxi\database
.\setup-mvp-demo.ps1

# 2. Backend
cd C:\TTaxi\backend
copy .env.example .env   # edit DB + JWT secrets — see MVP_DEMO_GUIDE.md
npm install
npm start

# 3. Frontend (dev)
cd C:\TTaxi\frontend
flutter pub get
flutter run -d chrome --web-port=8080

# 4. Verify
cd C:\TTaxi\backend
npm test
npm run rehearsal:mvp-e2e
cd C:\TTaxi\frontend
flutter test
flutter build web
```

## MVP direct URLs (dev)

| Screen | URL |
|--------|-----|
| Customer landing | http://localhost:8080/ |
| Guest lookup | http://localhost:8080/booking/lookup |
| Admin dispatch | http://localhost:8080/admin |
| Driver login | http://localhost:8080/driver |

## Demo accounts (dev/staging only)

| Role | Login | Password |
|------|-------|----------|
| Super Admin | `admin@ttaxi.dev` | `Admin123456!` |
| Driver | `+66810000001` (phone) | `Driver123456!` |

Created by `npm run seed:mvp-demo`. **Never use in production.**

## MVP known limitations

Not included in the current MVP demo:

- Payment processing
- Customer signup / member accounts
- Chat (customer–driver–admin)
- QR boarding / dropoff completion
- Socket.IO live sync (guest refresh is manual)
- Auto-dispatch
- Driver live GPS map

## License

Proprietary — T-Ride / TTaxi
