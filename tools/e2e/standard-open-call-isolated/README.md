# STANDARD / URGENT open-call isolated QA harness

Disposable stack: `tride-qa-admin-db`, internal `tride-qa-admin-net` (`Internal=true`), QA API containers **without** host `-p` publish. Scope: `/opt/t-ride` QA release paths only — never `/opt/ktaxi`, host nginx, or production DB.

## Primary entrypoints (verified path)

| Goal | Command |
|------|---------|
| **URGENT E2E** (gate=true matrix + gate=false smoke) | `bash run-urgent-isolated-suite.sh` |
| **Selftest** (no real Docker) | `bash verify-urgent-suite-shell.sh` |
| **Driver web UI — gate=false** | `KEEP_QA_RUNNING=1 bash run-driver-ui-gate-false.sh` |
| **Driver web UI — gate=true** | `run-driver-ui-gate-true-pre.sh` then `run-driver-ui-gate-true-post.sh <out-dir>` |
| **Teardown** | `bash stop-qa-ui.sh` |

Prerequisites on the staging host:

```bash
export BACKEND_ROOT=/opt/t-ride/releases/qa-backend-src
cd /opt/t-ride/releases/qa-standard-open-call/socket-qa && npm ci
```

See [README-URGENT-ISOLATED.md](./README-URGENT-ISOLATED.md) and [DRIVER-WEB-UI-MANUAL.md](./DRIVER-WEB-UI-MANUAL.md).

## QA driver password (never in git)

Fixtures hash the driver login password at runtime. Provide **one** of:

- `QA_DRIVER_PASSWORD` — session env on the QA host only, or
- `QA_DRIVER_PASSWORD_FILE` — mode `600` file, single line (preferred for manual UI runs)

If neither is set, suite/driver UI scripts generate an ephemeral file via `qa-bootstrap-driver-password.sh` (not printed to logs). For Flutter manual login on your PC, read the password **only on the server session** from the path echoed when using `KEEP_QA_RUNNING=1` (never commit or paste into chat).

Virtual fixture phones/emails: [qa-fixture-accounts.md](./qa-fixture-accounts.md).

## File categories (this tree)

| Category | Files |
|----------|--------|
| **URGENT/STANDARD runners** | `run-urgent-isolated-suite.sh`, `socket-qa/run-urgent-contact-dispatch-matrix.mjs`, `socket-qa/run-urgent-gate-false-smoke.mjs`, `socket-qa/run-contact-dispatch-matrix.mjs` (STANDARD matrix) |
| **Driver UI** | `run-driver-ui-gate-*.sh`, `run-ui-fixture.cjs`, `run-ui-api-verify.cjs`, `ui-flutter-qa.ps1` |
| **Shared helpers** | `run-urgent-isolated-lib.sh`, `qa-ui-common.sh`, `urgent-*.cjs`, `qa-ui-driver-auth.cjs`, `qa-driver-password.cjs`, `reset-db.sh`, `start-api-internal.sh`, `start-api.sh`, patch scripts |
| **Selftests** | `verify-urgent-suite-*.sh`, `verify-urgent-*-selftest.sh`, `test/fixtures/fake-docker-*.sh` |
| **Asserts** | `assert-urgent-*.cjs`, `assert-contact-dispatch-matrix.cjs` |

Excluded from this commit (legacy/superseded): host `orchestrate.sh`, `run-contact-dispatch-matrix.cjs` (bad SQL), staging deploy scripts, loopback/bridge runners, boundary/settlement suites, tarballs, debug-only tools.

## Backend under test

Copy product dispatch changes from `BACKEND_ROOT` with `apply-backend-patch.sh` + `verify-backend-patch.sh` (files listed in `qa-ui-common.sh`).
