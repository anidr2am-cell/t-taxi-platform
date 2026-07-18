# Customer driver live location staging E2E

This tool verifies the PR #43 customer-facing driver live location lifecycle in a real browser against staging. It is intentionally separate from `npm test` and `flutter test` because it creates a synthetic staging booking and drives that booking through trip states.

## Safety rules

- Staging only: `TRIDE_E2E_TARGET=staging` is mandatory.
- Production-like hosts are blocked by the runner. Allowed hosts are hardcoded to `trider.taxi`, `localhost`, and `127.0.0.1`.
- The allowed host list cannot be expanded with an environment variable. A new staging host must be reviewed as a code change.
- No production route, migration, Docker, nginx, KTaxi, pricing, settlement, QR, or background-location behavior is added.
- Secrets are loaded only from `.env.e2e.local`, which is ignored by git.
- Guest tokens are sent by header and redacted from logs, reports, and fixture markers.
- Cleanup archives only records whose run ID starts with `E2E-`, whose customer name starts with `[E2E]`, and whose marker contains `CUSTOMER_DRIVER_LOCATION_E2E`.
- Cleanup also reloads the booking from the existing admin booking detail API and verifies booking number, customer name, run ID, and server-side marker before archive.

## Required staging accounts

Use staging-only accounts:

- Admin: `tride.e2e.admin@example.com`
- Driver: `tride.e2e.driver@example.com`
- Driver ID for that exact test driver

Do not use real customer phone numbers or real driver accounts.

## Configuration

Copy the example file and fill only local secrets:

```powershell
Copy-Item .env.e2e.example .env.e2e.local
```

Set:

```text
TRIDE_E2E_TARGET=staging
TRIDE_E2E_FRONTEND_URL=https://trider.taxi
TRIDE_E2E_BACKEND_URL=https://trider.taxi
TRIDE_E2E_ALLOW_SPLIT_HOSTS=0
TRIDE_E2E_ADMIN_EMAIL=tride.e2e.admin@example.com
TRIDE_E2E_ADMIN_PASSWORD=<staging-only admin password>
TRIDE_E2E_DRIVER_EMAIL=tride.e2e.driver@example.com
TRIDE_E2E_DRIVER_PASSWORD=<staging-only driver password>
TRIDE_E2E_DRIVER_ID=<staging-only driver id>
TRIDE_E2E_CUSTOMER_PHONE=+66000000001
TRIDE_E2E_ALLOW_LIVE=1
```

## Commands

From `C:\TTaxi\backend`:

```powershell
npx playwright install chromium
npm run e2e:staging:customer-location:dry-run
npm run test:e2e-tools
```

Live staging run:

```powershell
npm run e2e:staging:customer-location
```

Headed debugging:

```powershell
npm run e2e:staging:customer-location -- --headed
```

Keep fixture for manual debugging:

```powershell
npm run e2e:staging:customer-location -- --headed --keep-fixture
```

If `--keep-fixture` is used, archive the test booking manually from the admin UI or run the tool again without `--keep-fixture` after confirming the booking is still an `[E2E]` booking.

## Scenario coverage

The runner:

1. Creates a separate synthetic booking for each viewport with an `E2E-...-<width>` run ID.
2. Looks up the booking from the customer lookup page.
3. Confirms `DRIVER_ASSIGNED` waits without a live marker.
4. Moves the trip to `ON_ROUTE`.
5. Sends driver location updates.
6. Verifies guest location polling is used instead of repeated guest lookup polling.
7. Verifies the browser WebSocket connection count separately from Engine.IO HTTP transport requests.
8. Checks customer-visible UI copy, marker semantics, raw localization keys, internal ID/token DOM leaks, and horizontal overflow.
9. Advances to `DRIVER_ARRIVED`, `PICKED_UP`, and `SETTLEMENT_PENDING`.
10. Verifies terminal UI cleanup and stops treating live tracking as active.
11. Reloads the booking through admin detail and archives only after server-side E2E marker validation.

The browser matrix is:

- 360 x 800
- 390 x 844
- 430 x 932
- 1280 x 800

## Network/security checks

The request observer verifies:

- No guest token in URL query strings.
- Guest driver location endpoint is called.
- Guest booking lookup endpoint is not used as a 15-second polling loop.
- Guest location requests keep the same token fingerprint without writing the token to console or artifacts.
- Socket HTTP transport requests are not treated as WebSocket connections.
- Browser WebSocket connections do not repeatedly reconnect for the same active state.

The backend/frontend unit tests remain the stronger proof for:

- No guest token insert during location polling.
- Internal `driverId` / `userId` omission from public guest payload.
- Terminal status cleanup.
- Stale location handling.

## Artifacts

Default artifact folder:

```text
e2e-artifacts/
```

The runner writes a redacted fixture manifest after a live run. It does not write raw traces by default because request headers may contain tokens. Do not attach browser traces that contain headers unless they have been manually checked for secrets.

Each manifest entry contains only run ID, viewport, booking number, customer marker, cleanup status, and redacted cleanup errors. Tokens and passwords are never written.

## Manual QA checklist

Use this when a live E2E account is not available:

- Customer booking lookup page opens on staging.
- `DRIVER_ASSIGNED` shows waiting copy, not raw localization keys.
- `ON_ROUTE` shows the map and driver location card.
- Marker moves after a driver location update.
- Stale state clearly says the last known location is old.
- `SETTLEMENT_PENDING` hides/removes the live marker.
- No guest token appears in the URL.
- Mobile widths 360, 390, and 430 px have no horizontal overflow.

## Live run prerequisites

Before the first booking is created, the runner verifies:

- Admin login succeeds and the account has an admin role.
- Driver login succeeds and the account has the driver role.
- `TRIDE_E2E_DRIVER_ID` matches the logged-in driver account.
- The driver is active.
- The driver has no active job.
- The configured customer phone is a clearly fake staging number.

If any prerequisite fails, the runner stops before creating a booking.

## Cleanup behavior

The runner registers a partial fixture immediately after booking creation, before lookup and assignment. If lookup, assignment, browser setup, or a lifecycle assertion fails, the `finally` block still attempts cleanup for that fixture.

Cleanup is considered successful only after the archive API succeeds. A failed cleanup fails the E2E run and is reported in the redacted manifest. `--keep-fixture` is the only mode that intentionally skips archive; in that case, manually archive the booking from the admin UI after debugging.

## Live result wording

If local staging credentials are not available, report the result as:

```text
dry-run passed
unit tool tests passed
live E2E not run: local staging credentials were not provided
```

Do not report waiting UI, map rendering, marker movement, terminal cleanup, or responsive behavior as actually verified until the live command has run successfully.
