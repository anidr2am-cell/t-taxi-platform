# Isolated booking UX checks

Build the landing and use `deploy/scripts/build-frontend-preview.ps1` with the isolated HTTPS API/socket URL. Start `../customer-booking-ux/server.cjs` with `PORT=3190` and `PREVIEW_MARKER=booking-flow-refinement-20261122`. It serves only synthetic fixtures; no database, SMTP or real bookings.

Set `PREVIEW_URL` to that HTTPS preview, `QA_OUTPUT` to an artifact directory and `PLAYWRIGHT_MODULE` to the installed Playwright module if needed. Chrome is required.

- `node frontend/qa/booking-flow-refinement/browser.cjs`: seven booking locales, five steps, widths 360/390/430/1280; screenshot matrix and browser errors.
- `node frontend/qa/booking-flow-refinement/landing.cjs`: six landing locales, same widths; first action visibility and horizontal overflow.
- `node frontend/qa/booking-flow-refinement/interaction.cjs`: detail-pending/route skip/edit/back, manual no-flight and invalid time, flight midnight/failure/empty/delay, stale places and retry. Booking/payment/message submission blocked.
- `node frontend/qa/booking-flow-refinement/accessibility.cjs`: keyboard search, language context, browser back/reload, four services, reduced viewport, 150% text, sampled contrast.
- `node frontend/qa/booking-flow-refinement/regression.cjs`: fare failure/inquiry, capacity limit, option requote, DMK/dropoff and draft/language preservation. No submission.

These are desktop headless viewports, not physical-device or screen-reader certification. Fare/provider outputs are synthetic contract fixtures; live provider availability is not asserted. Do not point the fixture server or tests at production.
