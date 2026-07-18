# Customer driver live location staging E2E

This tool verifies the PR #43 customer-facing driver live location lifecycle in a real browser against staging. It is intentionally separate from `npm test` and `flutter test` because it creates a synthetic staging booking and drives that booking through trip states.

## Safety rules

- Staging only: `TRIDE_E2E_TARGET=staging` is mandatory.
- Production-like hosts are blocked by the runner. The default whitelist is `trider.taxi`, `localhost`, and `127.0.0.1`.
- No production route, migration, Docker, nginx, KTaxi, pricing, settlement, QR, or background-location behavior is added.
- Secrets are loaded only from `.env.e2e.local`, which is ignored by git.
- Guest tokens are sent by header and redacted from logs, reports, and fixture markers.
- Cleanup archives only records whose run ID starts with `E2E-`, whose customer name starts with `[E2E]`, and whose marker contains `CUSTOMER_DRIVER_LOCATION_E2E`.

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

1. Creates a synthetic booking with an `E2E-...` run ID.
2. Looks up the booking from the customer lookup page.
3. Confirms `DRIVER_ASSIGNED` waits without a live marker.
4. Moves the trip to `ON_ROUTE`.
5. Sends driver location updates.
6. Verifies guest location polling is used instead of repeated guest lookup polling.
7. Checks browser console/page errors.
8. Advances to `DRIVER_ARRIVED`, `PICKED_UP`, and `SETTLEMENT_PENDING`.
9. Confirms cleanup by archiving the synthetic booking.

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
- Socket connection does not repeatedly reconnect for the same active state.

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

The runner writes only redacted fixture markers when `--keep-fixture` is used. Do not attach raw browser traces that contain headers unless they have been manually checked for secrets.

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
