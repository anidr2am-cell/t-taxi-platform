# Project State

## Commercialization RC

- RC branch: `release/staging-commercialization-rc1`
- Functional baseline: `8ca1cf4522fd99314c3d3f85e34c9357c8a39a8a`
- Staging core E2E: confirmed before this documentation refresh
- Runtime: Flutter Web, Node.js API, MariaDB 10.11

## Completed

- Guest booking, Google Places, pricing, booking lookup
- Admin login, operations workbench, search/filter, dispatch and detail workspace
- Driver login, four-tab navigation, Today trip, button-based status transitions
- `SETTLEMENT_PENDING` flow, fixed 200 THB commission, transfer slip, admin approval
- Customer review in settlement-pending/completed states with tags and optional comment
- Admin review detail including raw comment and timestamp
- Append-only admin booking notes, admin-only access
- Booking chat and notifications
- Driver ownership, active-assignment, settlement-blocking, and privacy enforcement

## Official Status Flow

`PENDING -> CONFIRMED -> DRIVER_ASSIGNED -> ON_ROUTE -> DRIVER_ARRIVED -> PICKED_UP -> SETTLEMENT_PENDING -> COMPLETED`

The active commercial driver UX is button based. QR remains compatibility-only.

## Migration State

- `35_review_tags.sql`: review tags
- `36_admin_booking_notes.sql`: append-only admin notes
- `37_add_settlement_pending_booking_status.sql`: settlement enum compatibility for staging
- There is no settlement-pending migration numbered 31
- Full migration runners replay all numbered SQL and are not approved for existing commercial DBs

## Remaining Production Work

- Production domain and HTTPS
- Final production topology and release automation
- Automated DB backup and restore rehearsal
- Administrator account recovery runbook completion
- Production secrets, monitoring, alerting, and retention policy
