# Booking design preview QA

1. Use an isolated synthetic API only. Never point these scripts at production.
2. Start `frontend/qa/customer-booking-ux/server.cjs` with a free `PORT` and `PREVIEW_MARKER=booking-design-renewal-20261121`; it has no DB/SMTP/FCM.
3. Open a unique HTTPS tunnel and build with `deploy/scripts/build-frontend-preview.ps1 -ApiBaseUrl <preview> -SocketUrl <preview>`.
4. Set `PREVIEW_URL` and `QA_OUTPUT`, then run `node frontend/qa/booking-design/landing.cjs` and `interaction.cjs`. `PLAYWRIGHT_MODULE` can name an already installed Playwright module.
5. Existing `customer-booking-ux/browser.cjs` can exercise the release app; use widths 360/390/430/1280 for this review.

Screenshots and JSON checks are review evidence. Reduced viewport / injected 150% text is not a substitute for real mobile keyboard and screen-reader testing. Fixture prices illustrate the UI only; public production fare data remains authoritative.
