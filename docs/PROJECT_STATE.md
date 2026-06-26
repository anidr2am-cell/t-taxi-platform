# Project

TTaxi - Thailand Airport Transfer Platform

# Current Pack

Pack 10 complete — Flight Data Foundation for the booking wizard. Next: Pack 11 Driver Jobs MVP.

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
- [x] OpenAPI 3.1 spec (`docs/openapi/openapi.yaml`)
- [x] Flutter — landing page, booking wizard UI, theme, 5-language l10n, PWA manifest

# In Progress

- Booking create — guest token, `PAY_DRIVER`, boarding QR token, commission status fields; dropoff QR schema only (no service yet)
- Customer booking wizard — step flow exists; full E2E against live API incomplete
- Frontend split — new `BookingApiService` (`/api/v1`) vs legacy `ApiService` (`/api/*`) and old admin screen
- Public proxy routes — flight foundation complete; places, airports, golf route files still stubbed
- Chat / Socket.IO — handler skeleton only
- `database/migrate.ps1` runs through `15`; migration `16` exists but is not in the script

# Next Pack

Pack 11 — Driver Jobs MVP

Planned scope:

- Authenticated driver access
- Today’s assigned bookings
- Booking detail
- No QR scanning yet
- No map
- No navigation
- No location tracking
- No chat
- No commission settlement

# Environment Configuration

- `AVIATIONSTACK_API_KEY` required for live flight provider lookup
- `AVIATIONSTACK_BASE_URL` optional/defaulted
- `AVIATIONSTACK_TIMEOUT_MS` optional/defaulted

# Current Verification

- `npm test`: 22/22 passed
- Focused flight tests: 16/16 passed
- `git diff --check` passed
- Application loads without API key
- Missing API key endpoint returns `503 FLIGHT_PROVIDER_NOT_CONFIGURED`

# Architecture Status

Backend — 40%  
Frontend — 30%  
Database — 90%  
OpenAPI — 85%  
Admin — 15%  
Driver — 5%

# Business Decisions

- Guest booking supported — no JWT required; `guest_access_token` (hashed) returned once on create
- Customer pays driver directly — default `payment_method = PAY_DRIVER`; no online checkout in MVP
- Company income from driver commission — `commission_status`, `commission_amount`, receipt file fields on booking
- Boarding QR then dropoff QR — boarding token issued at create; dropoff token after pickup (designed; dropoff logic pending)
- Google Places via backend proxy — API key server-side only (routes not implemented)
- AviationStack flight search — backend proxy only; API key never exposed to frontend
- No online payment — `payment_status` stays `UNPAID`/`PAID` manual; `ONLINE` reserved for Phase 2
- Admin manual dispatch (MVP) — auto-assign weights in DB; driver routes not built
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
