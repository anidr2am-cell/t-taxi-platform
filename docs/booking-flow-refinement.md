# Customer booking flow refinement (2026-11-22)

Review only: no production deployment, database migration or customer messages.
Baseline: `e330dd45a1a7f5125810240ba23122fa66c87f2f` (PR #238).

## Reproduced and changed

- A confirmed landing route previously reopened route step 1. A named, coordinate-complete, non-golf route now enters schedule step 2; invalid/incomplete data falls back to route entry. Golf still needs course/package details. The existing five-step progress indicator reflects the actual current step. Route editing remains available in the fixed summary and keeps date, passengers, luggage and contacts.
- Flight lookup appeared in both route and schedule. It is now only in schedule for airport pickup, with mutually exclusive flight/manual panels. Lookup failure, empty matches or slow lookup offers manual entry without dropping flight input. No flight is required for manual progression. Existing departure-local date, Bangkok arrival conversion and selectable +50/0-minute pickup rules are unchanged.
- Korean pickup display uses 24 hours throughout schedule, summary, review and customer completion. Offset-bearing display values are converted to Bangkok; naive stored values retain their existing Bangkok wall-clock interpretation. API storage remains unchanged.
- Manual time entry is expandable and shares the selected time with the picker; invalid visible drafts block progression. Picker content scrolls above keyboard insets.
- Customer-only phone normalization uses pinned MIT `phone_numbers_parser 9.0.29` metadata derived from libphonenumber (https://pub.dev/packages/phone_numbers_parser). Country-specific prefixes, significant Italian zero, full international/00 input, separators and duplicated dial prefixes are covered. Validation checks plausible length and E.164 syntax, not number ownership or reachability. Existing administrator manual-call normalization is intentionally retained.
- Customer email/requests are optional in an expandable section; saved content opens it automatically. Guidance describes the actual messenger/booking-lookup/support process, without promising automatic Kakao messages or friend linking.
- Place selection distinguishes query/results/detail-pending/selected/failure. Pending landing selection disables progression; changed input invalidates the prior endpoint immediately; generation guards ignore stale search/detail responses. Retry and existing support remain available. External airport selections also invalidate pending widget responses.
- Existing official logo is visible in the booking header. Fixed summary gains route editing, desktop expansion, passengers/luggage and pending/calculating/inquiry fare labels.
- Existing BKK meeting instructions (name sign: Gate 3; no name sign: Gate 7) are presented per the deployed verified guide. DMK/UTP give general booking-specific guidance only; no invented terminal, floor, gate or picture.

## Already present and preserved

Four services, existing support channels and guest booking, four-hour session drafts, refresh/back preservation, quote invalidation/recommendation generation guards, three simultaneous vehicle quotes, capacity combination limits, collapsible mobile summary, representative fares from the public data API, analytics consent and attribution, existing SEO/canonical/URLs. No fare, capacity, payment, assignment, status, cancellation/refund, font, fallback, engine, renderer or Flutter index change.

## Verification and review

- `flutter test test/booking_flow_refinement_test.dart test/customer_messenger_email_test.dart test/pickup_datetime_selection_test.dart test/step_pickup_datetime_flight_lookup_test.dart test/flight_pickup_time_conflict_test.dart test/customer_russian_test.dart test/russian_booking_review_test.dart test/customer_booking_ux_test.dart`
- `npm run blog:build && npm run blog:test`
- Build with `deploy/scripts/build-frontend-preview.ps1`; requires isolated HTTPS API/socket URL and checks the generated bundle.
- Browser scripts in `frontend/qa/booking-flow-refinement/` require `PREVIEW_URL`, `QA_OUTPUT` and optionally `PLAYWRIGHT_MODULE`. Server: existing `frontend/qa/customer-booking-ux/server.cjs` with `PORT=3190`, `PREVIEW_MARKER=booking-flow-refinement-20261122`. Pure synthetic fixtures, no DB/SMTP/FCM/production network. Never use production as this server's upstream.
- Booking language matrix: ko/en/th/ja/zh/zh-TW/ru, five steps at 360/390/430/1280. Landing: six supported languages at the same widths. Interaction scenarios cover pending details, route skip/edit/back, no-flight manual input, invalid draft, midnight flight, failure/empty/delayed lookup fallback, stale search and retry. Browser screenshots use synthetic QA Hotel/QA Preview only.
- Physical iOS/Android keyboards, screen readers and live airline-provider correctness need separate device/provider acceptance; headless simulated viewports are not physical-phone validation. No conversion-rate improvement claim.

## Operator materials / remaining priorities

Before publishing new airport maps/photos, supply approved DMK/UTP terminal/floor/meeting-point text and licensed images. Existing booking-specific instructions remain authoritative. Native-language editorial review and real-device keyboard/accessibility review are recommended. Phone metadata must be periodically reviewed through an explicit dependency update.

## Deployment after separate approval / rollback

Frontend + static landing only; no migration or backend rollout. Confirm exact merge scope and green main CI; follow existing DB/uploads backup, SHA-256 and Drive-match checks. Preserve current frontend image/source identifier before changing anything. Build/recreate only frontend with `--no-deps`; never restart DB/proxy. Check public fare data, four service entry links, locale routes and these booking interactions without submitting a real booking/message/payment. Roll back by restoring the captured frontend image/source and rebuilding/recreating frontend alone; no SQL rollback required. The current review preview is not a production artifact.
