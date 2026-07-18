# Full trip + settlement staging E2E

This staging-only runner verifies one synthetic booking across the customer
location flow and the settlement approval lifecycle.

It intentionally starts from the current `main` branch helpers:

- `tools/e2e/customer-driver-location` for browser-based customer lookup,
  live driver location rendering, Socket.IO/network audit, and driver status
  transitions through `SETTLEMENT_PENDING`.
- `tools/e2e/settlement-lifecycle` for settlement money assertions, synthetic
  receipt PNG generation, and server-side approval-candidate validation.

The runner does not use real customers, real payments, real receipts, QR scans,
production domains, KTaxi/88taxi infrastructure, or direct DB writes.

## What it validates

For a single synthetic fixture, the runner checks:

1. customer booking creation;
2. customer booking lookup with guest access kept out of URLs;
3. admin assignment to the configured staging E2E driver;
4. customer browser location UI at `390x844`;
5. Socket.IO connection/reconnect guard from the customer location runner;
6. `ON_ROUTE`, `DRIVER_ARRIVED`, `PICKED_UP`, and `SETTLEMENT_PENDING`;
7. customer location marker update after driver location posts;
8. driver settlement money fields;
9. synthetic test receipt upload;
10. admin settlement approval candidate identity guard;
11. settlement approval;
12. final `COMPLETED` booking state;
13. driver active-job release;
14. fixture archive cleanup.

## Current limitation

This PR is based on latest `main` only. It does not depend on the unmerged
driver/admin settlement UI E2E PRs. Therefore, settlement receipt submission and
admin approval are verified through existing authenticated API calls plus
server-side identity guards, while the customer location portion remains
browser-based.

Once the separate UI E2E PRs are merged, this runner can be extended to drive
the driver receipt UI and admin approval UI directly.

## Safety requirements

Run only against staging:

```powershell
cd C:\TTaxi\backend
npm run e2e:staging:full-trip-settlement:dry-run
```

Live execution requires the existing staging E2E environment variables:

- `TRIDE_E2E_TARGET=staging`
- `TRIDE_E2E_FRONTEND_URL=https://trider.taxi`
- `TRIDE_E2E_BACKEND_URL=https://trider.taxi`
- `TRIDE_E2E_ALLOW_LIVE=1`
- staging E2E admin credentials
- staging E2E driver credentials
- `TRIDE_E2E_DRIVER_ID`
- fake Thai staging customer phone

```powershell
cd C:\TTaxi\backend
npm run e2e:staging:full-trip-settlement
```

The runner refuses unknown hosts, production-like hosts, `88taxi.net`, and
KTaxi-like hosts through the shared E2E URL guard.

## Artifacts and cleanup

The runner writes a redacted manifest:

```text
e2e-artifacts/full-trip-settlement-e2e-manifest.json
```

By default, the synthetic fixture is archived at the end. Use
`--keep-fixture` only for local debugging, and archive the fixture manually
after investigation.
