# Driver settlement UI staging E2E

This staging-only runner verifies the driver-facing Flutter Web settlement flow with
one synthetic booking and one synthetic receipt image.

## Scope

- Uses the existing staging E2E admin and driver accounts.
- Creates one `[E2E]` booking through the public booking API.
- Assigns the configured E2E driver through the admin API.
- Moves the booking through the driver lifecycle until `SETTLEMENT_PENDING`.
- Opens the real Flutter Web driver UI in a mobile viewport.
- Verifies the driver settlement detail shows:
  - customer payment total
  - company commission
  - driver expected income
  - `THB` currency text
- Uploads a runtime-generated PNG receipt through the driver UI.
- Captures redacted browser screenshots for the settlement detail, upload
  section, selected receipt, and submitted receipt states.
- Uses the admin API only after UI upload to approve the settlement and release the
  E2E driver.
- Archives the synthetic booking as `TEST_DATA` during cleanup.

## Safety

- Do not run this workflow against production.
- Do not use real customer, driver, admin, QR, receipt, or bank account data.
- The receipt file is generated at runtime and contains the markers:
  - `E2E TEST RECEIPT`
  - `NOT A REAL PAYMENT`
  - the run ID
- The redacted manifest intentionally excludes access tokens, passwords, phone
  numbers, receipt paths, and receipt bytes.
- The runner refuses to proceed when the configured E2E driver already has an
  active job.
- The cleanup path reuses server-side E2E identity checks before archiving.
- This runner shares the staging E2E driver with other live E2E workflows, so it
  must not run concurrently with customer-location or settlement-lifecycle live
  E2E.
- The runner opens a staging-only Flutter route,
  `/driver/e2e/settlement-detail?bookingNumber=...`, after seeding the existing
  driver session token into Flutter Web storage. The route is disabled unless the
  frontend is built with `TRIDE_ENABLE_E2E_ROUTES=true`.
- The hidden route still uses the existing driver settlement API and driver auth
  token; it does not bypass booking ownership or server-side authorization.
- Receipt selection and upload use semantic button locators. The manifest records
  one file chooser click and one upload click so repeated coordinate-click
  regressions are visible.

## Commands

From `C:\TTaxi\backend`:

```powershell
npm run test:driver-settlement-ui-e2e-tools
npm run e2e:staging:driver-settlement-ui:dry-run
npm run e2e:staging:driver-settlement-ui
```

Optional headed browser run:

```powershell
npm run e2e:staging:driver-settlement-ui -- --headed
```

For pre-merge PR validation without deploying frontend code, serve the local
Flutter Web build and proxy `/api` to staging, then point the runner at that
local URL:

```powershell
cd C:\TTaxi\frontend
flutter build web `
  --dart-define=APP_ENV=staging `
  --dart-define=API_BASE_URL=http://127.0.0.1:58002 `
  --dart-define=SOCKET_URL=http://127.0.0.1:58002 `
  --dart-define=TRIDE_ENABLE_E2E_ROUTES=true

# Start a local SPA server with /api and /socket.io proxy to staging.
# Then, from C:\TTaxi\backend:
$env:TRIDE_E2E_FRONTEND_URL='http://127.0.0.1:58002'
$env:TRIDE_E2E_ALLOW_SPLIT_HOSTS='1'
npm run e2e:staging:driver-settlement-ui
```

## Required environment

The runner reads the same staging E2E environment contract used by the settlement
lifecycle tools, including:

- `TRIDE_E2E_FRONTEND_URL`
- `TRIDE_E2E_BACKEND_URL`
- `TRIDE_E2E_ADMIN_EMAIL`
- `TRIDE_E2E_ADMIN_PASSWORD`
- `TRIDE_E2E_DRIVER_EMAIL`
- `TRIDE_E2E_DRIVER_PASSWORD`
- `TRIDE_E2E_DRIVER_ID`
- `TRIDE_E2E_CUSTOMER_PHONE`

Keep all secrets in the execution environment or local untracked env files. Never
commit them.

## Deployment impact

The test tool itself is non-runtime. The associated THB money display fix
requires a frontend rebuild after merge if staging should run the exact same UI
validated by this E2E. To run this UI E2E against staging, build the staging
frontend with `TRIDE_ENABLE_E2E_ROUTES=true`; production builds must leave that
flag disabled. Backend runtime, DB, Docker, nginx, and KTaxi are not changed by
this tool.
