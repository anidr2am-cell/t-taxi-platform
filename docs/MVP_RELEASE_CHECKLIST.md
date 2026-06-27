# TTaxi MVP Release Checklist (Pack 18)

Use this checklist before go-live. Items marked MVP limitation are intentional scope, not defects.

## Code and Git

- [ ] All Pack 18 verification tests pass locally and in CI
- [ ] Release tag created from known commit
- [ ] `.env` and secrets excluded from repository
- [ ] `backend/.env.example` copied and completed for target environment

## Database migrations

- [ ] Fresh MySQL database created for release verification
- [ ] `database/migrate.ps1` applied migrations **00–20** in order without errors
- [ ] Migration 20 appears exactly once after migration 19 in `migrate.ps1`
- [ ] Seed migrations (`11_seed.sql`, `17_settlement_settings_seed.sql`) verified idempotent (no admin overwrite)
- [ ] Production backup taken before first production migration

## Environment variables

See `backend/.env.example` for full list.

**Required (all environments):**

- [ ] `DB_USER`, `DB_NAME`, `DB_PASSWORD` (production password non-empty)
- [ ] `JWT_ACCESS_SECRET`, `JWT_REFRESH_SECRET` (min 16 chars, strong random values)

**Required in production:**

- [ ] `NODE_ENV=production`
- [ ] `CORS_ORIGIN` set to explicit frontend origin(s) — not `*`
- [ ] `SWAGGER_ENABLED=false`
- [ ] `PUBLIC_API_URL` set to public API base

**Optional (safe to leave empty in MVP):**

- [ ] `GOOGLE_MAPS_API_KEY` — Places proxy disabled without key
- [ ] `AVIATIONSTACK_API_KEY` — flight lookup returns provider-unavailable safely
- [ ] `SMTP_*` — email notifications skipped
- [ ] `FIREBASE_*` — FCM push skipped

**Frontend build defines:**

- [ ] `API_BASE_URL` points to production API
- [ ] `SOCKET_URL` points to production Socket.IO host

## Backend startup

- [ ] `npm install` in `backend/`
- [ ] Application starts with production `.env` without validation errors
- [ ] Health check `GET /api/v1/health` returns OK
- [ ] Optional integrations log skip messages instead of crashing
- [ ] Upload directory (`UPLOAD_DIR`) exists and is writable

## Frontend build

- [ ] `flutter pub get`
- [ ] `flutter analyze` — no errors
- [ ] `flutter test` — all pass
- [ ] `flutter build web --dart-define=API_BASE_URL=... --dart-define=SOCKET_URL=...`
- [ ] PWA loads against production API (not localhost)

## Admin account setup

- [ ] At least one `ADMIN` or `SUPER_ADMIN` user exists
- [ ] Admin can log in via Dispatch tab (stores `admin_access_token`)
- [ ] Protected admin tabs (chat, settlements, reviews, notifications) accessible after login

## Driver account setup

- [ ] At least one active driver user linked to `drivers` table
- [ ] Driver can log in (stores `driver_access_token`)
- [ ] Driver without overdue blocking settlement can receive assignment

## Test booking (end-to-end)

- [ ] Customer/guest creates booking via wizard
- [ ] Boarding QR shown on confirmation page
- [ ] Admin assigns driver from dispatch queue
- [ ] Driver marks arrived
- [ ] Driver scans boarding QR → `PICKED_UP`
- [ ] Customer/guest issues dropoff QR after pickup
- [ ] Driver scans dropoff QR → `COMPLETED`

## Settlement test

- [ ] Commission obligation appears once after completion
- [ ] Driver uploads receipt (JPG/PNG/PDF within size limit)
- [ ] Admin approves receipt
- [ ] Driver assignment eligibility restored after approval

## Review test

- [ ] Guest/customer submits review via header/body token (never URL)
- [ ] Duplicate review rejected (`REVIEW_ALREADY_SUBMITTED`)
- [ ] Driver rating summary shows aggregate only

## Notification test

- [ ] Guest booking notifications visible with `X-Guest-Access-Token` header
- [ ] Driver/admin in-app notifications created for operational events
- [ ] Notification failure does not roll back booking/settlement (post-commit outbox)

## Chat test

- [ ] Customer/guest chat loads REST history and receives Socket.IO messages live
- [ ] Driver chat works on assigned booking
- [ ] Admin chat queue + detail work after admin login
- [ ] Reassigned driver cannot send or receive new messages
- [ ] Terminal bookings (`COMPLETED`, `CANCELLED`, `NO_SHOW`) are read-only

## Upload storage

- [ ] Settlement receipts stored under configured `UPLOAD_DIR` (default `./uploads`)
- [ ] Receipt files served only through authenticated download endpoints — **not** public static hosting
- [ ] **Production warning:** local disk uploads are lost on redeploy unless `UPLOAD_DIR` is on persistent volume or migrated to object storage (not implemented in MVP)

## Domain and HTTPS

- [ ] API served over HTTPS
- [ ] Frontend served over HTTPS
- [ ] Socket.IO uses WSS through same host or configured reverse proxy

## CORS

- [ ] `CORS_ORIGIN` matches deployed frontend origin
- [ ] `X-Guest-Access-Token` allowed for browser guest flows
- [ ] Credentials/cookies behavior verified if used

## Logging and monitoring

- [ ] Log directory writable (`LOG_DIR`)
- [ ] Production responses do not include stack traces
- [ ] JWT, guest tokens, and QR raw tokens not present in logs
- [ ] Basic uptime monitoring on `/api/v1/health`

## Backup and rollback

- [ ] Database backup schedule configured
- [ ] Upload directory backup or persistence plan documented
- [ ] Rollback procedure documented (revert deploy + restore DB backup)

## Known MVP limitations (not release blockers)

- No payment gateway — customer pays driver directly
- Manual admin dispatch only — no automatic dispatch
- No live driver map or GPS tracking
- Local receipt file storage — plan persistent volume or object storage for production
- No continuous background outbox worker — startup recovery only
- EMAIL and FCM delivery may be disabled — in-app notifications only
- No SMS/WhatsApp notifications
- Chat is text-only; admin chat queue list requires manual refresh for new threads
- No customer global inbox for authenticated customers (guest booking-scoped flows)
- Message sending uses REST; Socket.IO provides real-time receive/read updates
- Offline chat send queue not persisted across app restarts
- Legacy `/api/v1/chat/*` routes return deprecation 404 — use booking-scoped chat APIs

## Go-live sign-off

| Role | Name | Date | Approved |
|------|------|------|----------|
| Engineering | | | [ ] |
| Operations | | | [ ] |
| Product | | | [ ] |
