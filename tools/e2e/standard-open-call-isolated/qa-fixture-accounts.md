# QA fixture accounts (virtual data only)

All identifiers below are **synthetic** for isolated QA DB `tride_qa_admin`. They are not real customers or drivers.

| Role | Email | Phone | User id | Notes |
|------|-------|-------|---------|--------|
| Admin | `qa-oc-admin@example.invalid` | — | 1 | Minted JWT in suite |
| Customer | `qa-oc-customer@example.invalid` | — | 2 | Minted JWT |
| Driver (UI / clean) | `qa-oc-driver-clean@example.invalid` | `1111111` | 10 | `run-ui-fixture.cjs`, driver web UI |
| Driver (socket / busy) | `qa-oc-driver-socket@example.invalid` | `1111111002` | 11 | URGENT/socket matrix default |

Login uses **`users.phone`** for `POST /auth/login`. Password is **not** stored in this repo — set `QA_DRIVER_PASSWORD` or `QA_DRIVER_PASSWORD_FILE` at runtime (see [README.md](./README.md)).
