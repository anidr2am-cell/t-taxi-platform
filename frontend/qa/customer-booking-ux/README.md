# Isolated customer UX preview

This fixture is for review and browser tests only. It is not a staging database or a production fare engine. It uses the real compiled customer app and real recommendation service with synthetic rules; place, flight and price responses are fixtures. No DB, SMTP, FCM or production Docker network is used. Public channel/landing snapshots and the company WeChat QR contain no customer records.

1. Install root and backend npm dependencies and Flutter dependencies.
2. Build `landing/build.cjs` and start `node frontend/qa/customer-booking-ux/server.cjs` (127.0.0.1:3188).
3. Expose only that server through an isolated HTTPS preview origin.
4. Build with the origin guard:

```powershell
./deploy/scripts/build-frontend-preview.ps1 -ApiBaseUrl $PreviewOrigin -SocketUrl $PreviewOrigin
$env:PREVIEW_URL = $PreviewOrigin
$env:QA_OUTPUT = 'C:/TTaxi-screens/customer-booking-ux/after'
node frontend/qa/customer-booking-ux/browser.cjs
node frontend/qa/customer-booking-ux/landing-browser.cjs
node frontend/qa/customer-booking-ux/completion-browser.cjs
node frontend/qa/customer-booking-ux/edge-browser.cjs
```

Chrome is launched headlessly in a separate test profile; these are not real-phone tests. Override PLAYWRIGHT_MODULE / QA_BROWSER_CHANNEL where necessary. Set QA_LANGUAGES for a focused wizard-language rerun. The fixture response header is `X-Preview-Backend: customer-booking-ux-20261121-fixture`.

Do not point these scripts at production. Completion tests create only in-memory `QA-PREVIEW-*` rows. They intercept external messenger navigation, verify that opening a channel leaves it PENDING, then simulate the customer's own sent confirmation as CONFIRM_REQUESTED, never VERIFIED. One scenario discards an accepted creation response and verifies that retry uses the same idempotency key. No mail or push send implementation exists in this server.

All fixtures are cleared when this standalone server stops. No production login or credentials are needed. Use dummy names and contact values only.
