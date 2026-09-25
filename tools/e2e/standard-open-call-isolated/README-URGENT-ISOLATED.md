# URGENT isolated E2E (QA only)

Uses the same disposable stack as STANDARD open-call QA: `tride-qa-admin-db`, internal `tride-qa-admin-net`, `start-api-internal.sh`, backend patch from `BACKEND_ROOT`.

## Product flow (code references)

| Step | State / event |
|------|----------------|
| Customer creates `bookingMode: 'URGENT'` | `contact_status`: `PENDING` if `CONTACT_CONNECTION_REQUIRED=true`, else `VERIFIED`; negotiation row `BROADCASTING` inserted |
| Customer `confirm-sent` | `contact_status` → `CONFIRM_REQUESTED` (not dispatch) |
| Admin `POST .../contact/verify` | `contact_status` → `VERIFIED`; `dispatchAfterContactVerified` → `driver:urgent-call:new` + `DRIVER_URGENT_CALL_NEW` notifications |
| gate=false create | No deferral: immediate `emitDriverUrgentCallNew` on commit |

Pickups for URGENT must be **within 2 hours** (`validateUrgentScheduledPickupAt`).

Driver socket auth in this suite: **`POST /auth/login`** with `users.phone` (not minted driver JWT).

## Prerequisites (host, before suite)

```bash
cd /opt/t-ride/releases/qa-standard-open-call/socket-qa
npm ci   # bundle node_modules — suite does NOT npm install inside internal QA containers
```

## Run on staging host

```bash
cd /opt/t-ride/releases/qa-standard-open-call
export BACKEND_ROOT=/opt/t-ride/releases/qa-backend-src
bash run-urgent-isolated-suite.sh
```

Matrix/smoke JSON is written to stdout files only; stderr goes to `*.stderr.log`. Assert runs via **container Node**, not host Node.

Artifacts: `urgent-isolated-<UTC>/` with JSON matrix + smoke results.

## Teardown

Suite exits non-zero on failure and removes QA API containers + stops DB unless `KEEP_QA_RUNNING=1`.

```bash
docker rm -f tride-qa-admin-api tride-qa-oc-true-api
docker stop tride-qa-admin-db
```

Recreating API containers changes container IP — refresh SSH tunnel if used for manual UI.

## Not covered here

- URGENT timeout worker / lock-ETA round trips (see `backend/scripts/staging-urgent-timeout-hardening-e2e.js`)
- Driver Flutter UI countdown / auto-refresh
- M3 placeholder removal
