# Customer booking design renewal

Base: 8e6d013f2e204e53cae0b3f07c3edf306702cc11. Review preview only; no production deployment.

## Observed problems and priority

A read-only production capture at 390×844 placed the primary form button at y=904–958; at 360 it was the same, and at 430 it was y=868–922. The service cards lived in a long introductory column separate from the route form. Yellow secondary support competed with the teal online action, mobile navigation used small labels, and the representative fare table did not offer a route-selection action. Existing language/session transfer worked and is retained.

P0: unified booking panel, first-screen action, safe cookie/keyboard placement and route continuity. P1: legible navigation, costs and reference vehicle imagery, clear airport and post-booking guidance. P2: information hierarchy, policy wording and measurement review.

## Navigation and customer flow

Desktop: Book a transfer → Fares & vehicles → Find booking → Help & support → language. Mobile keeps booking lookup and language visible; a primary bottom action provides booking access without a hamburger dependency. Service direction is explicit for airport pickup/drop-off, city transfers and accommodation–golf-course transfers.

Landing service + origin/destination → existing five-step app: route → schedule (flight/manual as existing) → passengers/luggage, suitable vehicles, options/final quote → contacts → review. No new booking step or required field. The primary action explains the next screen. Booking lookup remains available from the customer app bar. Completion continues to use actual server state and existing lookup/meeting/driver guidance.

Selecting a representative fare fills the airport and destination search hint, not an invented hotel location. A real search-result address remains required. The complete route then uses the existing expiring session handoff. No fixed-price calculation or rate rule changed.

## Shared design criteria

- Existing logo and existing font stack/Flutter font assets retained. No font, fallback, engine, renderer or Flutter index.html changes.
- Primary #0B6E6E / dark #084F50; body #1E2A32, secondary #475D69; backgrounds #FFFFFF/#F4F7F8; border #CBD7DD.
- Primary filled teal; support outlined teal; auxiliary links lower emphasis. Customer booking button paint is scoped to that page; admin and driver themes unchanged.
- 16px body/input baseline; 28px mobile heading / 44px desktop heading; 48–52px form/action targets and at least 44px auxiliary controls. 12px controls / 16–20px panels. Long translations may wrap.
- Focus outline 3px teal; per-field invalid indication and live lookup status. Bottom action avoids the measured cookie banner and is hidden for a reduced visual viewport while editing. Full content has bottom clearance. Native field editing remains unchanged.
- Vehicle images are the existing user-provided sedan/SUV/van reference assets, labelled as reference, not assigned vehicles. No competitor images, manufactured testimonials, ratings or credentials.

## Content and data

The public landing API remains the live fare/channel source. Refresh the checked-in fallback only by reading that public endpoint: 22 rows before/after and no price differences. Its source/date now reflect production, not an old preview hostname. Fare selection does not create a reservation. Currency, route and per-vehicle context are retained with address/option conditions nearby.

Three cost/payment/delay facts precede expandable details. Avoid unverified automatic-adjustment/response-time guarantees; cancellation, payment and pricing business rules remain unchanged. Cash/card identical final fees were not newly claimed because payment processor/administrator conditions require separate confirmation.

Lookup guidance replaces a misleading messenger-only third step. BKK/DMK/UTP are distinguished, with booking-specific meeting instructions; no BKK gate copied to another airport. Buddy Golf: Korean join/solo/group advice through the provided golf Kakao link; overseas private rounds for at least two actual players; transport-only has no minimum and does not confirm a tee time. Official customer support settings are reused. No sending code or persistent production settings changed.

## Preservation and verification

Existing URLs, canonical/hreflang, structured FAQ data, internal links, campaign attribution allowlist and analytics consent are retained. Some misleading title suffixes now name tolls/airport parking specifically. Existing language/session storage expiry and booking idempotency remain. No DB, server booking/payment/dispatch code, or customer notification logic changes.

Reproducible isolated checks: frontend/qa/booking-design/landing.cjs and interaction.cjs. Set PREVIEW_URL, QA_OUTPUT and optionally PLAYWRIGHT_MODULE. The synthetic server accepts PORT and PREVIEW_MARKER so it remains separate from production. Run the mandatory deploy/scripts/build-frontend-preview.ps1 origin check before browser QA. Synthetic QA creates no production data; no SMTP/FCM connection exists.

Tests include 360/390/430/1280 landing layouts, initial cookie clearance, four service intents, route-address safety, keyboard search/focus, language/back/reload persistence, reduced viewport and 150% text, contrast. Existing Flutter tests cover vehicle suitability, service summaries, completion and booking flow. Browser regressions exercise seven booking languages and five steps. Real iPhone/Android keyboard and assistive technology remain an explicit follow-up, not a claimed pass.

## Conversion measurement (not a promise)

No new tracker or event is introduced. Use existing consented landing_booking_start, booking_started, booking_step_viewed, booking_step_completed, booking_submitted and booking_completed events, retaining existing deduplication and PII sanitization. Compare equal 14-day windows before/after approval, grouped by language, device, service and campaign. Report entry rate and per-step drop-off with counts/denominators and traffic differences; do not infer a conversion improvement from prettier screens or a small sample. Server-success completion and UI clicks must remain distinct.

## Deployment after separate approval

Frontend only, no migration. Verify only this PR is pending, preserve previous HEAD/image, DB+uploads backup, SHA-256 and Drive verification. Rebuild/recreate frontend only with --no-deps; do not restart backend/DB/proxy. Roll back to the preserved frontend image and prior source; no data rollback. Keep the isolated review preview until approval.
