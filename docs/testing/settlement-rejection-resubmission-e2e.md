# Settlement rejection and resubmission staging E2E

This staging-only API runner verifies the rejected receipt lifecycle for one
synthetic settlement fixture.

## Scope

- Uses the existing staging E2E admin and driver accounts.
- Creates one `[E2E]` booking through the public booking API.
- Assigns the configured E2E driver through the admin API.
- Moves the booking through the driver lifecycle until `SETTLEMENT_PENDING`.
- Uploads synthetic receipt V1 through the driver settlement API.
- Rejects V1 through the admin settlement API with a synthetic reason.
- Verifies the driver settlement API exposes:
  - `REJECTED`
  - the rejection reason
  - no active receipt metadata
- Uploads synthetic receipt V2 through the driver settlement API.
- Verifies V2 has a different active receipt file ID, clears the rejection
  reason, and restores admin `canApprove=true`.
- Re-reads admin booking and settlement details before approval.
- Approves through the admin settlement API.
- Verifies booking `COMPLETED`, settlement `APPROVED`, driver active job release,
  and fixture archive cleanup.

## Synthetic receipts

The runner creates tiny runtime PNG files only. They contain:

```text
E2E TEST RECEIPT V1
NOT A REAL PAYMENT
run ID
```

and:

```text
E2E TEST RECEIPT V2
NOT A REAL PAYMENT
run ID
```

No real receipt, QR, payment, bank account, or customer document is used.

## Safety

- Do not run this workflow against production.
- The runner hard-allows only staging/localhost hosts through the shared E2E
  config.
- The configured E2E driver must be active, online, available, and have no active
  job before a fixture is created.
- Approval is gated by server-side E2E identity checks immediately before the
  approval API call.
- Cleanup archives only after server-side booking number, `[E2E]` customer name,
  marker, and run ID validation.
- The redacted manifest intentionally excludes access tokens, passwords, phone
  numbers, receipt paths, and receipt bytes.
- This runner shares the staging E2E driver with other live E2E workflows, so it
  must not run concurrently with customer-location, settlement-lifecycle,
  driver-settlement, or admin-settlement live E2E.

## Commands

From `C:\TTaxi\backend`:

```powershell
npm run test:settlement-rejection-e2e-tools
npm run e2e:staging:settlement-rejection:dry-run
npm run e2e:staging:settlement-rejection
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
e2e-artifacts/settlement-rejection-resubmission-e2e-manifest.json
```

Allowed fields are limited to synthetic booking identifiers and redacted status
metadata. Never store tokens, passwords, customer phone, bank data, signed URLs,
headers, cookies, or raw receipt bytes.

## Deployment impact

The runner is non-runtime test tooling only. Backend runtime, frontend runtime,
DB, Docker, nginx, and KTaxi are not changed by this tool.
