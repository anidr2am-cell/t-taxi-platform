# Project

TTaxi - Thailand Airport Transfer Platform

# Current Pack

Pack 15 complete — Review and Rating MVP. Next: Pack 16 Notification Foundation MVP.

# Completed

- [x] Architecture & API design docs (`ARCHITECTURE`, `DATABASE_DESIGN`, `API_CONTRACT`, `BUSINESS_ENGINE`, `ADMIN_OPERATION_SYSTEM`)
- [x] MySQL migrations `00`–`18` (booking hub, charge items, chat, notifications, routes/locations pricing, QR & commission columns, settlement settings seed, reviews)
- [x] Backend skeleton — Express, JWT middleware, Joi validation, Swagger UI, health check
- [x] Auth API — register, login, refresh, logout, `/auth/me`
- [x] Booking APIs — `POST /bookings/vehicle/recommend`, `POST /bookings/pricing/calculate`, `POST /bookings`
- [x] Admin pricing API — routes, vehicle prices, charge policies, simulate
- [x] Pricing engine — `locations` → `routes` → `vehicle_prices` + `charge_policies` (no hardcoded prices)
- [x] Vehicle recommendation engine — DB `vehicle_capacity_rules`
- [x] Pack 10 Flight Data Foundation — public flight search `GET /api/v1/public/flights/search`
- [x] Aviationstack integration through backend only — flight number/date validation, provider response normalization, internal flight status mapping, arrival delay calculation, deterministic multiple-result selection, timeout/error mapping
- [x] Flight lookup reliability — five-minute in-memory success cache, cache mutation protection, provider errors/not-found not cached
- [x] OpenAPI flight endpoint documentation, focused flight service tests, `docs/OPERATION_FLOW.md` restored
- [x] Pack 11 Driver Jobs MVP — authenticated DRIVER-only access
- [x] Driver jobs API — `GET /api/v1/driver/bookings/today`, `GET /api/v1/driver/bookings/:bookingNumber`
- [x] Driver job security — active-assignment ownership enforcement and safe not-found response for another driver's booking
- [x] Driver job responses — Thailand service-day filtering, pickup-time sorting, minimal booking list, assigned booking detail
- [x] Flutter driver MVP — driver login, today's jobs, booking detail, loading/empty/error/refresh states
- [x] Driver OpenAPI documentation, focused backend driver tests, Flutter tests
- [x] Pack 12 Driver QR Operation MVP — driver QR operation and customer dropoff QR delivery
- [x] Driver QR API — `POST /api/v1/driver/bookings/:bookingNumber/arrive`, `POST /api/v1/driver/bookings/:bookingNumber/scan-boarding`, `POST /api/v1/driver/bookings/:bookingNumber/scan-dropoff`
- [x] Customer dropoff QR API — `POST /api/v1/bookings/:bookingNumber/dropoff-qr/issue`
- [x] Driver QR security — authenticated DRIVER role enforcement, active assignment ownership, safe not-found for another driver's booking
- [x] Driver lifecycle operations — `DRIVER_ASSIGNED` to `DRIVER_ARRIVED`, `DRIVER_ARRIVED` to `PICKED_UP`, `PICKED_UP` to `COMPLETED`
- [x] QR lifecycle reliability — atomic QR consumption/status transition, idempotent arrival/scans, duplicate-scan protection, events after commit only
- [x] Customer QR issuance — guest/customer-authorized dropoff QR issuance, rotation invalidates previous unused QR, hashes stored only, raw QR tokens not exposed through driver APIs
- [x] Flutter QR operation — driver Mark Arrived, boarding/dropoff scanner, manual token fallback, loading/success/retry/error states
- [x] Customer QR UI — boarding QR display, dropoff QR issue/display after `PICKED_UP`, completed state hides active dropoff QR
- [x] Pack 13 Admin Dispatch MVP — manual admin dispatch for ADMIN and SUPER_ADMIN
- [x] Admin dispatch API — `GET /api/v1/admin/bookings`, `GET /api/v1/admin/bookings/:bookingNumber`, `POST /api/v1/admin/bookings/:bookingNumber/assign-driver`, `POST /api/v1/admin/bookings/:bookingNumber/reassign-driver`, `GET /api/v1/admin/drivers`
- [x] Admin dispatch authorization — JWT required; ADMIN and SUPER_ADMIN only
- [x] Admin booking queue — search, status/date/assignment filters, sorting, pagination
- [x] Admin booking detail — operational route, customer, passengers, luggage, vehicle, flight, pricing, status history, assignment history, allowed actions
- [x] Admin driver list — eligibility states (ACTIVE, INACTIVE, NOT_ELIGIBLE), active assignment counts
- [x] Manual assignment — initial assign and reassignment with reason; exactly one active assignment after success
- [x] Assignment concurrency — booking row locking, active assignment locking, conflict handling
- [x] Assignment status transitions — `BookingStatusService` only; atomic assignment + status change; lifecycle and `driver.reassigned` events after commit
- [x] Admin response safety — QR hashes, guest token hashes, and secrets excluded from admin responses
- [x] Booking number validation — `TX` plus 12 digits aligned across generator, services, and validators
- [x] Flutter admin dispatch — booking queue, search/filters, pagination/load-more, booking detail, assign/reassign dialogs, inactive/ineligible driver indication, loading/empty/error/refresh states, duplicate-submit prevention, 401 session clearing with return to admin login
- [x] Admin rail — reservations entry connected to Admin Dispatch queue
- [x] Admin dispatch OpenAPI — queue item schema, booking detail schema, driver list, assign/reassign requests, pagination and authorization documentation
- [x] Pack 14 Commission Settlement MVP — driver commission obligation after trip completion
- [x] Commission obligation activated after `COMPLETED`; idempotent `trip.completed` settlement handler; reconciliation for missed completion events (driver list/detail, admin list/detail)
- [x] Driver settlement API — list, detail, receipt upload, protected receipt download
- [x] Admin settlement API — queue, detail, receipt access, approve, reject
- [x] Commission configuration — `settlement.commission_rate_percent` and `settlement.commission_due_days` from settings; no hardcoded commission amount
- [x] Receipt storage — transactional database updates, receipt replacement, old receipt soft deletion, safe generated filenames, MIME and extension validation, path traversal protection, no server filesystem paths returned
- [x] Overdue and blocking — derived public overdue status; server-side driver assignment blocking for overdue unpaid commission; assignment eligibility restored when all blocking settlements are approved
- [x] Settlement authorization — protected receipt access for DRIVER (own bookings), ADMIN, and SUPER_ADMIN; reviewer and driver identity from JWT only
- [x] Migration `17_settlement_settings_seed.sql`; `database/migrate.ps1` updated through migration 17
- [x] Flutter driver settlement — list, detail, real JPG/JPEG/PNG/PDF file selection, receipt upload and replacement, rejected and approved states, loading/empty/error/retry/duplicate-submit prevention
- [x] Flutter admin settlement — queue, detail, receipt review, approve and reject flows
- [x] Settlement OpenAPI documentation and focused backend/Flutter tests
- [x] Pack 15 Review and Rating MVP — customer reviews after `COMPLETED`
- [x] Reviews schema — `database/18_reviews.sql`; one review per booking (`UNIQUE booking_id`); rating 1–5; optional comment max 500 characters; `VISIBLE`/`HIDDEN` moderation
- [x] Review eligibility — authenticated customer ownership or guest token scoped to booking; no access by booking number alone
- [x] Guest token transport — lookup via `X-Guest-Access-Token` header only; submission via JSON body only; never in URL or query parameters
- [x] Customer review API — `GET /api/v1/bookings/:bookingNumber/review`, `POST /api/v1/bookings/:bookingNumber/review`
- [x] Driver rating API — `GET /api/v1/driver/rating-summary` (aggregate only: `averageRating`, `reviewCount`)
- [x] Admin review API — `GET /api/v1/admin/reviews`, `GET /api/v1/admin/reviews/:reviewId`, `POST /api/v1/admin/reviews/:reviewId/hide`, `POST /api/v1/admin/reviews/:reviewId/restore`
- [x] Review submission reliability — booking row locking, driver identity from assignment, duplicate protection (`REVIEW_ALREADY_SUBMITTED`), transaction-safe insert and audit log
- [x] Rating aggregation — `VISIBLE` reviews only; one-decimal average; hidden excluded immediately; restored included again; no denormalized driver rating storage
- [x] Admin moderation — hide with required reason, restore, audit logs; hidden reason and reviewer identity admin-only
- [x] Migration `18_reviews.sql`; `database/migrate.ps1` updated through migration 18
- [x] Flutter customer review — form after `COMPLETED`, 1–5 stars, optional comment, loading/retry/success/already-submitted states, refresh restores submitted state, duplicate-submit prevention
- [x] Flutter driver rating summary card — average and count only; no individual comments
- [x] Flutter admin reviews — queue with rating/status/search filters, detail, hide/restore with confirmation, loading/empty/error/refresh states
- [x] Review OpenAPI documentation and focused backend/Flutter tests
- [x] OpenAPI 3.1 spec (`docs/openapi/openapi.yaml`)
- [x] Flutter — landing page, booking wizard UI, theme, 5-language l10n, PWA manifest

# In Progress

- Booking create — guest token, `PAY_DRIVER`, boarding QR token, commission status fields
- Customer booking wizard — step flow exists; full E2E against live API incomplete
- Frontend split — new `BookingApiService` (`/api/v1`) vs legacy `ApiService` (`/api/*`) and old admin screen
- Public proxy routes — flight foundation complete; places, airports, golf route files still stubbed
- Chat / Socket.IO — handler skeleton only

# Legacy Issues

- Unused legacy `_buildReservations` in `admin_screen.dart`
- Pre-existing `use_build_context_synchronously` infos in legacy reservation actions

# Intentionally Deferred

- Online customer payment
- Payment gateway integration
- Automatic bank verification
- Scheduled overdue processing
- Public review browsing
- Driver review replies
- Rewards, points, coupons, and loyalty
- Notifications (Pack 16 scope)
- Chat
- AI moderation
- Denormalized rating storage on drivers
- Driver access to individual review comments
- Maps and live tracking
- Automatic dispatch
- Kanban drag and drop

# Next Pack

Pack 16 — Notification Foundation MVP

Planned scope:

- Event-driven notification records
- In-app notification inbox
- Booking and operational notification events
- Customer, driver, and admin notification targeting
- Read/unread state
- No WhatsApp or SMS integration
- No marketing notifications
- Email and FCM delivery may remain adapters or stubs if credentials are unavailable

# Environment Configuration

- `AVIATIONSTACK_API_KEY` required for live flight provider lookup
- `AVIATIONSTACK_BASE_URL` optional/defaulted
- `AVIATIONSTACK_TIMEOUT_MS` optional/defaulted

# Current Verification

- Backend `npm test`: 143/143 passed
- Focused review tests (`review.test.js`): 36/36 passed
- Focused settlement tests (`commissionSettlement.test.js`): 29/29 passed
- Focused admin dispatch tests: 18/18 passed
- Flutter full tests: 39/39 passed
- Focused Flutter review and rating tests: 13/13 passed
- Flutter analyze (affected review and driver files): no issues
- OpenAPI YAML: review sections updated and readable
- `git diff --check`: passed
- Migration 18 appears exactly once after migration 17 in `database/migrate.ps1`

# Architecture Status

Backend — 50%  
Frontend — 40%  
Database — 92%  
OpenAPI — 92%  
Admin — 40%  
Driver — 30%

# Business Decisions

- Guest booking supported — no JWT required; `guest_access_token` (hashed) returned once on create
- Customer pays driver directly — default `payment_method = PAY_DRIVER`; no online checkout in MVP
- Company income from driver commission — `commission_status`, `commission_amount`, receipt file fields on booking; obligation created after completion; admin approves receipt proof
- Boarding QR then dropoff QR — boarding token issued at create; dropoff token issued to authorized customer/guest after pickup; driver scans QR to complete trip
- Google Places via backend proxy — API key server-side only (routes not implemented)
- AviationStack flight search — backend proxy only; API key never exposed to frontend
- No online payment — `payment_status` stays `UNPAID`/`PAID` manual; `ONLINE` reserved for Phase 2
- Admin manual dispatch (MVP) — auto-assign weights in DB; manual assign/reassign implemented in Pack 13
- Prices from DB only — route × vehicle + charge policies; admin CRUD for rules
- Customer reviews after completion — one review per booking; guest token in header (lookup) or body (submit), never in URL; driver sees aggregate rating only
- Architecture is frozen — Controller → Service → Repository; business logic in services only

# Development Rules

- Do not hardcode prices or vehicle rules — read from DB (`vehicle_capacity_rules`, `routes`, `vehicle_prices`, `charge_policies`)
- Everything configurable in Admin — pricing, routes, surcharges, capacity rules
- Architecture is frozen — do not rewrite layers or folder structure
- Controller: HTTP only; Service: business logic; Repository: SQL only
- Align API with OpenAPI / `API_CONTRACT.md`; validators match request bodies
- Keep Cursor token usage low — minimal scope, no drive-by refactors
- Return only changed files in edits
- Do not regenerate existing docs unless explicitly requested
- No secrets in code — `.env` only
- Do not commit unless asked

Development Principles

1.
Is it needed now?

2.
Does it simplify operation?

3.
Does it increase revenue?

4.
Does it encourage repeat usage?

5.
Does it strengthen platform lock-in?

6.
Does it reduce customer anxiety?

7.
Can it be reused by future services?

Only implement features that satisfy most of these principles.
