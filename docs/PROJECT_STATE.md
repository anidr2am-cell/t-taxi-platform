# Project

TTaxi - Thailand Airport Transfer Platform

# Current Pack

Booking MVP — customer reservation flow with route-based pricing, guest access, and boarding QR on create. Backend business engines (vehicle recommend, pricing, booking orchestration) plus admin pricing CRUD. Customer Flutter booking wizard (new `/api/v1` path) replacing legacy screens.

# Completed

- [x] Architecture & API design docs (`ARCHITECTURE`, `DATABASE_DESIGN`, `API_CONTRACT`, `BUSINESS_ENGINE`, `ADMIN_OPERATION_SYSTEM`)
- [x] MySQL migrations `00`–`16` (booking hub, charge items, chat, notifications, routes/locations pricing, QR & commission columns)
- [x] Backend skeleton — Express, JWT middleware, Joi validation, Swagger UI, health check
- [x] Auth API — register, login, refresh, logout, `/auth/me`
- [x] Booking APIs — `POST /bookings/vehicle/recommend`, `POST /bookings/pricing/calculate`, `POST /bookings`
- [x] Admin pricing API — routes, vehicle prices, charge policies, simulate
- [x] Pricing engine — `locations` → `routes` → `vehicle_prices` + `charge_policies` (no hardcoded prices)
- [x] Vehicle recommendation engine — DB `vehicle_capacity_rules`
- [x] OpenAPI 3.1 spec (`docs/openapi/openapi.yaml`)
- [x] Flutter — landing page, booking wizard UI, theme, 5-language l10n, PWA manifest

# In Progress

- Booking create — guest token, `PAY_DRIVER`, boarding QR token, commission status fields; dropoff QR schema only (no service yet)
- Customer booking wizard — step flow exists; full E2E against live API incomplete
- Frontend split — new `BookingApiService` (`/api/v1`) vs legacy `ApiService` (`/api/*`) and old admin screen
- Public proxy routes — places, flights, airports, golf (route files stubbed)
- Chat / Socket.IO — handler skeleton only
- `database/migrate.ps1` runs through `15`; migration `16` exists but is not in the script

# Next Pack

1. Finish booking lifecycle API — GET guest/member booking, cancel, status transitions, QR verify & dropoff QR generation  
2. Implement public proxies — `/places/*`, `/flights`, `/airports`, `/golf-courses`  
3. Wire customer wizard E2E and retire legacy `/api` client paths  
4. Admin MVP — dashboard, booking list, manual driver assign (per `ADMIN_OPERATION_SYSTEM.md`)

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
- AviationStack flight tracking — proxy planned; not implemented
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
