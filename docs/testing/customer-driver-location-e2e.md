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

## Manual GitHub Actions run

The workflow file is:

```text
.github/workflows/staging-customer-location-e2e.yml
```

It is intentionally manual-only:

- Trigger: `workflow_dispatch`
- No `push` trigger
- No `pull_request` trigger
- No `schedule` trigger
- Environment: `staging-e2e`
- Runner: GitHub-hosted `ubuntu-latest`
- Timeout: 20 minutes
- Concurrency group: `staging-customer-location-e2e`
- `cancel-in-progress: false`

`cancel-in-progress` is disabled because every live run uses the same staging E2E driver and creates temporary synthetic bookings. A newer run must wait for the active run to finish so that the runner can complete its cleanup sweep.

Run it manually after the workflow exists on the selected branch:

```powershell
gh workflow run staging-customer-location-e2e.yml --ref main
```

For a PR branch, GitHub may not expose a newly added workflow in the Actions UI until the workflow file exists on the default branch. If GitHub does not allow running it by branch ref, merge the workflow first and then run it manually from `main`.

Do not run this workflow against production. The workflow pins:

```text
TRIDE_E2E_TARGET=staging
TRIDE_E2E_FRONTEND_URL=https://trider.taxi
TRIDE_E2E_BACKEND_URL=https://trider.taxi
TRIDE_E2E_ALLOW_SPLIT_HOSTS=0
TRIDE_E2E_ALLOW_LIVE=1
TRIDE_E2E_KEEP_FIXTURE=0
```

The CI workflow does not pass `--keep-fixture`. Cleanup is always expected to run.

## GitHub environment secrets

Configure these as `staging-e2e` environment secrets, not production secrets:

```text
TRIDE_E2E_ADMIN_EMAIL
TRIDE_E2E_ADMIN_PASSWORD
TRIDE_E2E_DRIVER_EMAIL
TRIDE_E2E_DRIVER_PASSWORD
TRIDE_E2E_DRIVER_ID
TRIDE_E2E_CUSTOMER_PHONE
```

Do not write secret values into this document, the workflow file, commit messages, PR comments, command-line arguments, or artifacts. If setting secrets with `gh`, pass values through stdin or the interactive prompt.

Example command shape only:

```powershell
gh secret set TRIDE_E2E_ADMIN_EMAIL --env staging-e2e
gh secret set TRIDE_E2E_ADMIN_PASSWORD --env staging-e2e
gh secret set TRIDE_E2E_DRIVER_EMAIL --env staging-e2e
gh secret set TRIDE_E2E_DRIVER_PASSWORD --env staging-e2e
gh secret set TRIDE_E2E_DRIVER_ID --env staging-e2e
gh secret set TRIDE_E2E_CUSTOMER_PHONE --env staging-e2e
```

The workflow checks only whether required secrets are present. It must not print secret values or lengths.

## GitHub Actions artifact policy

The workflow uploads only:

```text
e2e-artifacts/customer-location-e2e-manifest.json
```

The manifest is redacted by the runner and retained for 7 days. The workflow writes, scans, validates, summarizes, and uploads the same repository-root artifact path through:

```text
TRIDE_E2E_ARTIFACT_DIR=${{ github.workspace }}/e2e-artifacts
```

If the live E2E step reaches fixture creation, the manifest is required. A missing or empty manifest fails the workflow, and upload uses `if-no-files-found: error` so artifact path mistakes are visible.

Do not upload:

- `.env.e2e.local`
- raw Playwright traces
- HAR/network dumps
- cookies
- localStorage/sessionStorage dumps
- raw request headers
- raw response bodies
- screenshots that expose real customer data
- access tokens, guest tokens, passwords, API keys, or private keys

## Cleanup and manual cancellation

The runner archives synthetic fixtures through the existing admin archive API after server-side E2E marker validation. It does not directly update or delete DB rows.

Manual cancellation can still kill the process before the final cleanup sweep completes. If a workflow is manually cancelled or times out, inspect the redacted manifest if it exists, then check staging for unarchived synthetic bookings whose:

- booking number belongs to a staging E2E run,
- customer name starts with `[E2E]`,
- marker contains the customer location E2E marker,
- payment is not completed,
- settlement is not in progress,
- active operational assignment count is zero.

Only then archive with the existing admin archive API. Do not directly update/delete DB rows.

An assignment history row with `is_active=1` is not by itself an operational active job if the parent booking is archived. Operational active-job checks require:

```text
booking is not archived
assignment is_active=1
assignment deleted_at is null
```

Headed debugging:

```powershell
npm run e2e:staging:customer-location -- --headed
```

Run one supported viewport for repeatable diagnostics:

```powershell
npm run e2e:staging:customer-location -- --viewport=1280x800
```

Supported viewport values are:

- `360x800`
- `390x844`
- `430x932`
- `1280x800`

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
7. Verifies the browser Socket.IO WebSocket lifecycle separately from Engine.IO HTTP transport requests and unrelated browser WebSockets.
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
- Socket.IO browser WebSocket connections do not overlap or reconnect silently for the same active scenario.
- Other browser WebSockets are recorded separately and excluded from the customer Socket.IO assertion.
- Socket lifecycle records store only category, sanitized origin/path, sequence, lifecycle stage, and open/close timestamps. Query strings, Socket.IO `sid`, headers, frames, and payloads are never recorded.
- Overlapping duplicate Socket.IO connections fail immediately.
- Sequential Socket.IO reconnects fail with lifecycle context, for example the stage that opened, closed, and reopened the connection.

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
