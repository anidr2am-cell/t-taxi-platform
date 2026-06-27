# Project

TTaxi - Thailand Airport Transfer Platform

# Current Pack

Pack 13 complete — Admin Dispatch MVP. Next: Pack 14 Commission Settlement MVP.

# Completed

- [x] Architecture & API design docs (`ARCHITECTURE`, `DATABASE_DESIGN`, `API_CONTRACT`, `BUSINESS_ENGINE`, `ADMIN_OPERATION_SYSTEM`)
- [x] MySQL migrations `00`–`16` (booking hub, charge items, chat, notifications, routes/locations pricing, QR & commission columns)
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
- [x] `database/migrate.ps1` — migrations `00` through `16` including `16_booking_qr_settlement.sql`
- [x] Flutter admin dispatch — booking queue, search/filters, pagination/load-more, booking detail, assign/reassign dialogs, inactive/ineligible driver indication, loading/empty/error/refresh states, duplicate-submit prevention, 401 session clearing with return to admin login
- [x] Admin rail — reservations entry connected to Admin Dispatch queue
- [x] Admin dispatch OpenAPI — queue item schema, booking detail schema, driver list, assign/reassign requests, pagination and authorization documentation
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

- Automatic dispatch
- Kanban drag and drop
- Live map and driver tracking
- Chat
- Notifications
- Commission settlement (Pack 14 scope)
- Reviews

# Next Pack

Pack 14 — Commission Settlement MVP

Planned scope:

- Create commission obligation after trip completion
- Driver settlement queue
- Receipt upload
- Admin receipt review
- Approve or reject settlement
- Driver eligibility blocking when commission is overdue
- No automatic payment gateway
- No online customer payment

# Environment Configuration

- `AVIATIONSTACK_API_KEY` required for live flight provider lookup
- `AVIATIONSTACK_BASE_URL` optional/defaulted
- `AVIATIONSTACK_TIMEOUT_MS` optional/defaulted

# Current Verification

- Backend `npm test`: 78/78 passed
- Focused driver QR tests: 16/16 passed
- Focused admin dispatch tests: 18/18 passed
- Flutter admin dispatch tests: 8/8 passed
- Flutter full tests: 21/21 passed
- Flutter analyze (admin dispatch): no issues
- OpenAPI YAML parse: passed
- `git diff --check`: passed
- `database/migrate.ps1` PowerShell parser validation: passed

# Architecture Status

Backend — 45%  
Frontend — 35%  
Database — 90%  
OpenAPI — 90%  
Admin — 35%  
Driver — 25%

# Business Decisions

- Guest booking supported — no JWT required; `guest_access_token` (hashed) returned once on create
- Customer pays driver directly — default `payment_method = PAY_DRIVER`; no online checkout in MVP
- Company income from driver commission — `commission_status`, `commission_amount`, receipt file fields on booking
- Boarding QR then dropoff QR — boarding token issued at create; dropoff token issued to authorized customer/guest after pickup; driver scans QR to complete trip
- Google Places via backend proxy — API key server-side only (routes not implemented)
- AviationStack flight search — backend proxy only; API key never exposed to frontend
- No online payment — `payment_status` stays `UNPAID`/`PAID` manual; `ONLINE` reserved for Phase 2
- Admin manual dispatch (MVP) — auto-assign weights in DB; manual assign/reassign implemented in Pack 13
- Prices from DB only — route × vehicle + charge policies; admin CRUD for rules
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
