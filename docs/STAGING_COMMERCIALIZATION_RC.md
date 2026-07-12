# Staging Commercialization RC

## Purpose

This document fixes the operational baseline for T-Ride commercialization staging and separates verified behavior from remaining production work.

## RC Baseline

- Branch: `release/staging-commercialization-rc1`
- Functional commit: `8ca1cf4522fd99314c3d3f85e34c9357c8a39a8a`
- Documentation-inclusive RC commit: the commit containing this document; verify with `git rev-parse HEAD`
- Staging path: `/opt/t-ride`
- Test booking used for the confirmed RC flow: `TX202607120002`

## Official Status Flow

`PENDING -> CONFIRMED -> DRIVER_ASSIGNED -> ON_ROUTE -> DRIVER_ARRIVED -> PICKED_UP -> SETTLEMENT_PENDING -> COMPLETED`

Admin assigns a driver. Driver uses buttons for departure, arrival, customer pickup, and trip end. Trip end creates `SETTLEMENT_PENDING`; it does not complete the booking. Customer QR scanning is not the current commercial UX. Remaining QR code is compatibility-only.

## Customer Flow

Customer creates and looks up a booking, follows driver status, and can review a resolved driver in `SETTLEMENT_PENDING` or `COMPLETED`. One review is allowed per booking: rating 1-5, tags, and optional comment up to 500 characters.

Customers do not receive commission, receipt, admin approval, internal notes, or operations issue information.

## Driver Flow

Driver uses Today and the four-tab shell. Active assignment ownership is enforced. An unsettled job blocks another assignment. Drivers see the 200 THB obligation and upload a transfer slip, but do not receive raw customer review comments, negative tags, admin issue reasons, or internal notes.

## Admin Flow

The operations workbench includes Needs action, Unassigned, Today, Upcoming, In progress, Settlement, Completed, Cancelled, and All views. Booking detail contains status/next action, internal notes, customer, trip, driver/vehicle, fare/settlement, chat, review, history, and technical information.

Internal notes are append-only, include author/time, and have no edit/delete action.

## Settlement Policy

- Trip end: booking `SETTLEMENT_PENDING`, commission `DUE`, amount 200 THB
- Approval unavailable until a receipt file exists and server reports approval eligibility
- Admin previews and approves the transfer slip
- Approval: booking `COMPLETED`, commission `PAID`
- Receipt linkage remains after approval
- Source of truth: booking commission fields, `commission_receipt_file_id`, file row, and receipt metadata; no separate settlement table

## Review Policy

Eligibility requires `SETTLEMENT_PENDING` or `COMPLETED`, resolved driver, no existing review, and valid guest/customer access. Admin sees rating, tags, raw comment, created time, and low-rating issue. Driver privacy rules remain enforced.

## Staging Infrastructure

- `tride-db`: MariaDB 10.11, private DB
- `tride-backend`: host 3100
- `tride-frontend`: host 3101
- Customer: `http://103.60.127.213:3101/`
- Lookup: `http://103.60.127.213:3101/booking/lookup`
- Driver: `http://103.60.127.213:3101/driver`
- Admin: `http://103.60.127.213:3101/admin`
- Health: `http://103.60.127.213:3100/api/v1/health`

## Selective Deployment And Migration

Documentation-only changes require no deployment. Runtime releases rebuild only changed `tride-*` services.

The migration runners replay all numbered SQL and have no migration history table. Do not run them wholesale against an existing commercial DB. Back up the explicit target, inspect schema, apply only missing SQL, and validate after each file.

Staging selectively applied `37_add_settlement_pending_booking_status.sql`. Production must inspect its booking status enum before applying migration 32 or 37. No `31_settlement_pending` file exists.

## Minimum E2E

- Customer booking/lookup, no QR guidance, status sync, review submit and duplicate block
- Driver assignment, button transitions, settlement pending, receipt upload, assignment block
- Admin workbench, assignment, receipt approval, completed/paid, review detail, internal note
- Customer/driver privacy and cross-driver access controls

## Confirmed RC Evidence

For `TX202607120002`: booking `COMPLETED`, commission `PAID`, amount 200 THB, receipt linkage retained, one review with rating 2, customer completion card shown, and admin review tags/comment/timestamp shown. Driver did not receive raw review or negative tags; customer did not receive settlement or internal-note data. Backend health, frontend HTTP 200, all three T-Ride containers, and legacy isolation were reported healthy before this document refresh.

## Non-Blocking Warnings

- Booking analyze has one existing info
- Admin dispatch analyze has three existing deprecation infos
- Production domain/HTTPS not configured
- Production deployment topology not finalized
- Staging test data remains
- Administrator recovery procedure incomplete
- Automated DB backup/restore not rehearsed

## Production Remaining Work

Finalize domain/TLS, production topology, secrets, monitoring, backup/restore rehearsal, administrator recovery, data retention, and production migration preview.

## Rollback

Rollback triggers include booking creation failure, driver transition failure, settlement mismatch, receipt failure, review failure, access-control leakage, or service health failure. Record `PREVIOUS_HEAD`, switch only T-Ride to that release, rebuild only affected services, and verify health. Do not automatically reverse migrations, restore the full DB during live traffic, tear down the stack, or touch legacy KTaxi.

## RC Result

Decision: **PASS WITH NON-BLOCKING WARNINGS**

No critical or high issue was known in the verified staging baseline. Main integration may be considered after diff/security/migration audit; production release remains conditional on the operational work above.
