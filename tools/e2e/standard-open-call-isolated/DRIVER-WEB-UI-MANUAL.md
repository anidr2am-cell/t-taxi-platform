# Driver web UI — isolated STANDARD QA (manual)

Scope: **QA only** (`tride-qa-admin-api` / `tride-qa-oc-true-api`, `tride-qa-admin-db`). Do not change production DB, KTaxi, or host nginx.

## QA driver login (no secrets in logs)

| Field | Where to find it |
|--------|------------------|
| Phone | `ui-manifest.json` → `driverLoginPhone` (default **`1111111`**, driver user **10**) |
| Email | `qa-oc-driver-clean@example.invalid` (seed in `run-ui-fixture.cjs`) |
| Password | Runtime only: `QA_DRIVER_PASSWORD` or `QA_DRIVER_PASSWORD_FILE` (mode 600). Ephemeral file path is printed when using `KEEP_QA_RUNNING=1` — read on the **server session** only; never commit or paste into chat/README. |
| Phone field | Backend login uses **`users.phone`** (`findDriverByPhone`), not `drivers.phone` alone — UI fixture sets both. |

## Network isolation check (after start)

QA API must be **only** on `tride-qa-admin-net` (**Internal=true**), **no** host port publish, **no** `bridge`:

```bash
docker network inspect tride-qa-admin-net --format 'Internal={{.Internal}}'
docker inspect tride-qa-admin-api --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}'
docker port tride-qa-admin-api 3000/tcp   # expect empty
API_IP=$(docker inspect tride-qa-admin-api --format '{{(index .NetworkSettings.Networks "tride-qa-admin-net").IPAddress}}')
curl -sS "http://${API_IP}:3000/api/v1/health"
```

Container IP changes when the API container is recreated — always read it from `docker inspect` (do not hardcode).

## Server — gate=false (keep QA for Flutter)

```bash
cd /opt/t-ride/releases/qa-standard-open-call
KEEP_QA_RUNNING=1 bash run-driver-ui-gate-false.sh
```

On success, the script prints the **Windows SSH tunnel** with the live API IP and keeps API/DB up.

Artifacts: printed `out=/opt/t-ride/.../ui-gate-false-<UTC>/` (`ui-manifest.json`, `ui-api-verify.json`, `patch-verify.log`).

## Server — gate=true (two steps; run only when you intentionally switch gate)

**Pre** (pending customer hidden; **no** admin verify yet):

```bash
KEEP_QA_RUNNING=1 bash run-driver-ui-gate-true-pre.sh
```

Manual Flutter checks against `ui-api-pre.json`, then **post**:

```bash
bash run-driver-ui-gate-true-post.sh /opt/t-ride/releases/qa-standard-open-call/ui-gate-true-<UTC>
```

(use the exact `out=` directory from pre)

## PC — SSH tunnel

Use the tunnel line from `KEEP_QA_RUNNING=1` output (container IP on staging). Form:

```powershell
ssh -N -o ExitOnForwardFailure=yes -L 127.0.0.1:13001:<QA_API_IP>:3000 tride-staging
```

Health on PC: `curl -sS http://127.0.0.1:13001/api/v1/health`

## PC — Flutter web

```powershell
cd c:\TTaxi\frontend
flutter run -d chrome --web-port=8088 `
  --dart-define=API_BASE_URL=http://127.0.0.1:13001 `
  --dart-define=SOCKET_URL=http://127.0.0.1:13001 `
  --dart-define=APP_ENV=development
```

Open `http://127.0.0.1:8088/driver/login`.

## Server — teardown when done

```bash
bash /opt/t-ride/releases/qa-standard-open-call/stop-qa-ui.sh
```

## API vs UI PASS

- **API PASS** = `ui-api-verify.json` / pre/post JSON has `"allPass": true`.
- **UI PASS** = you confirm each open-call card booking number matches `visibleBookingNumbers` in that JSON.
