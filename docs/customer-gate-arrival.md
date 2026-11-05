# BKK Gate 7 arrival alert

Scope: AIRPORT_PICKUP, BKK, without NAME_SIGN. Existing name-sign Gate 3 flow stays unchanged. No fare, booking status, assignment, settlement or customer-contact exposure changes. No migration.

## Customer flow

A language-specific `/booking/lookup?bookingNumber=...&lang=...&arrival=gate7` link is included in existing booking-created/confirmed/driver-assigned emails and can be copied by an admin (six selectable languages). Existing booking access authentication is required. Link previews and GET requests never send alerts. Once authenticated, the Gate 7 action is brought into view. The customer collects all luggage, reaches outside Arrival Gate 7, then confirms a POST. Available after active driver assignment, within 24 hours before/after pickup, before pickup starts. Other cases show support guidance.

Only the current active assigned driver receives a Thai notification. No customer phone/email/messenger ID is in the payload. Existing persistent notification/delivery tables are reused. Booking-row locking plus assignment-scoped idempotency avoids double-click/reload duplicates. A reassignment receives a separate key. Recovery checks the current assignment and trip status, skipping stale delivery. Push is best effort: accepted/recorded is not handset receipt or driver departure. The read marker only means marked read in the notification list (including mark-all-read), not explicit driver acknowledgement.

## Driver readiness

A Thai/Korean guide is visible in the driver shell. Drivers must install the PWA as an operating procedure, launch its Home Screen icon, log in, and allow notifications. iPhone requires iOS 16.4+ Home Screen web app for Web Push; Android Chrome also offers browser push, but the installed-icon workflow avoids in-app browser confusion. Installation alone does not guarantee alerts. Check notification permissions, sound, Focus/Do Not Disturb, connectivity and battery settings. The guide links to the notification inbox; unread arrivals are also checked while the web UI is open (20s). No acceptance, online/offline, suspension or schedule-conflict rules change.

References: https://webkit.org/blog/13878/ ; https://firebase.google.com/docs/cloud-messaging/web/receive-messages

## Verification and deployment

Do not send real notifications or customer email during QA. The isolated `tools/qa/gate-arrival/server.cjs` uses a new MariaDB with only one synthetic booking. The real arrival service and notification persistence run, but outbound FCM/SMTP are explicitly disabled. The QA frontend entry uses production widgets. It is NOT evidence of a real phone receiving push.

Before any production release: verify Firebase web build config and VAPID, backend FCM credentials, active web device registration; test a dedicated QA handset in background/locked mode on Android and iPhone, inspect Thai message and click target. Never report push fully operational from a successful HTTP POST alone. Any missing config/handset validation is a release blocker for claiming reliable push readiness.

Production deployment requires separate approval. Follow existing backup + Drive checksum/count verification, backend then frontend --no-deps; never restart DB/proxy. No migration. Roll back code/images using recorded predeployment images; retain notification history. Do not replay successful alerts or customer emails.
