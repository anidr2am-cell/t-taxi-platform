# Admin settlement approval UI staging E2E

This staging-only runner verifies the admin-facing Flutter Web approval path for
one synthetic settlement fixture.

## Scope

- Uses the existing staging E2E admin and driver accounts.
- Creates one `[E2E]` booking through the public booking API.
- Assigns the configured E2E driver through the admin API.
- Moves the booking through the driver lifecycle until `SETTLEMENT_PENDING`.
- Uploads a runtime-generated synthetic PNG receipt through the driver API.
- Re-reads admin booking and settlement detail before opening the admin UI.
- Refuses to click UI approval unless the server confirms:
  - booking number
  - `[E2E]` customer name
  - E2E marker and run ID
  - configured E2E driver assignment
  - booking status `SETTLEMENT_PENDING`
  - settlement and receipt status `RECEIPT_SUBMITTED`
  - `canApprove=true`
- Opens the real Flutter Web admin settlement detail UI.
- Clicks the visible approval action and confirmation dialog.
- Verifies by API that the booking is `COMPLETED`, settlement is `APPROVED`,
  and the driver has no active job.
- Archives the synthetic booking as `TEST_DATA` during cleanup.

## Safety

- Do not run this workflow against production.
- Do not use real customer, driver, admin, QR, receipt, or bank account data.
- The receipt file is generated at runtime and contains only:
  - `E2E TEST RECEIPT`
  - `NOT A REAL PAYMENT`
  - the run ID
- The redacted manifest intentionally excludes access tokens, passwords, phone
  numbers, receipt paths, and receipt bytes.
- Approval is gated by server-side E2E identity checks immediately before the UI
  click.
- Cleanup reuses server-side E2E identity checks before archiving.
- This runner shares the staging E2E driver with other live E2E workflows, so it
  must not run concurrently with customer-location, settlement-lifecycle, or
  driver-settlement live E2E.

## Flutter Web route note

Flutter Web release builds currently expose little usable DOM semantics for this
screen. To avoid unsafe "first card" or `nth()` interactions in the admin queue,
the runner uses a local PR Flutter build with:

```text
TRIDE_ENABLE_E2E_ROUTES=true
```

That build flag exposes only a test-only direct route:

```text
/admin/e2e/settlement-detail?bookingNumber=TX...
```

The route is disabled by default and is not required for normal staging or
production builds.

## Commands

From `C:\TTaxi\backend`:

```powershell
npm run test:admin-settlement-ui-e2e-tools
npm run e2e:staging:admin-settlement-ui:dry-run
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
npm run e2e:staging:admin-settlement-ui
```

Optional headed browser run:

```powershell
npm run e2e:staging:admin-settlement-ui -- --headed
```

## Required environment

The runner reads the same staging E2E environment contract used by the settlement
lifecycle tools, including:

- `TRIDE_E2E_TARGET`
- `TRIDE_E2E_FRONTEND_URL`
- `TRIDE_E2E_BACKEND_URL`
- `TRIDE_E2E_ADMIN_EMAIL`
- `TRIDE_E2E_ADMIN_PASSWORD`
- `TRIDE_E2E_DRIVER_EMAIL`
- `TRIDE_E2E_DRIVER_PASSWORD`
- `TRIDE_E2E_DRIVER_ID`
- `TRIDE_E2E_CUSTOMER_PHONE`
- `TRIDE_E2E_ALLOW_LIVE`

Keep all secrets in the execution environment or local untracked env files. Never
commit them.

## Manifest

Default artifact:

```text
e2e-artifacts/admin-settlement-ui-e2e-manifest.json
```

Allowed fields are limited to synthetic booking identifiers and redacted status
metadata. Never store tokens, passwords, customer phone, bank data, signed URLs,
headers, cookies, or raw receipt bytes.

## Deployment impact

The test tool itself is non-runtime. The hidden E2E route is disabled unless
`TRIDE_ENABLE_E2E_ROUTES=true` is explicitly supplied at build time. Backend
runtime, DB, Docker, nginx, and KTaxi are not changed by this tool.
