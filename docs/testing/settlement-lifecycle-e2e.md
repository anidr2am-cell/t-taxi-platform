# Staging settlement lifecycle E2E

This staging-only runner verifies the commercial driver settlement approval path with a synthetic booking.

It covers:

- synthetic booking creation with `[E2E] Settlement Customer`
- admin driver assignment
- driver transitions through `ON_ROUTE`, `DRIVER_ARRIVED`, `PICKED_UP`
- driver `end-trip` to `SETTLEMENT_PENDING`
- 200 THB company commission and driver expected income fields
- synthetic transfer-slip upload
- admin settlement detail and receipt metadata
- admin approval to booking `COMPLETED` and public settlement `APPROVED`
- driver active-job release
- archive cleanup through the existing admin archive API

## Commands

```powershell
cd C:\TTaxi\backend

npm run test:settlement-e2e-tools
npm run e2e:staging:settlement:dry-run
npm run e2e:staging:settlement
```

The live command requires the same staging E2E account variables as the customer-location E2E runner and `TRIDE_E2E_ALLOW_LIVE=1`.

## Safety

- The runner hard-allows only staging/localhost hosts and blocks production-like hosts.
- It uses a run ID starting with `E2E-SETTLEMENT-`.
- It uses marker `SETTLEMENT_LIFECYCLE_E2E`.
- It creates a synthetic PNG receipt at runtime only.
- The PNG contains only:
  - `E2E TEST RECEIPT`
  - `NOT A REAL PAYMENT`
  - the run ID
- No real payment, bank account, customer document, QR, or receipt is used.
- Cleanup archives only after server-side booking number, `[E2E]` customer name, marker, and run ID validation.
- The manifest stores only redacted lifecycle status fields.

## Manifest

Default artifact:

```text
e2e-artifacts/settlement-lifecycle-e2e-manifest.json
```

Allowed fields:

- `runId`
- `bookingNumber`
- `settlementStatus`
- `receiptStatus`
- `approvalStatus`
- `bookingFinalStatus`
- `preparationStatus`
- `preparationError`
- `cleanupStatus`
- `cleanupError`

Never store tokens, passwords, customer phone, bank data, signed URLs, headers, cookies, or raw receipt bytes.

## Current storage cleanup policy

The booking fixture is archived through the admin API. Uploaded settlement receipt files follow the existing application storage policy; the runner does not directly delete DB rows or filesystem objects.
