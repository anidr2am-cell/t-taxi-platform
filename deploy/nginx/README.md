# Nginx — T-Ride staging configs (reference)

These files describe the **same-origin** pattern (Flutter static + `/api/` proxy + SPA fallback). They are **templates**, not something to install blindly on every server.

## Gabia VPS (shared with legacy KTaxi)

On the **Gabia** server that runs **`ktaxi-nginx`** on host **80/443**:

- **Do not** install host nginx or bind host 80/443 for T-Ride.
- **Do not** copy these files to `/etc/nginx/` on the host.
- T-Ride uses Docker at **`/opt/t-ride`** with containers **`tride-*`**.
- **`tride-frontend`** container nginx should follow the same `location /` + `location /api/` pattern as below.
- Public domain **`tride-staging.88taxi.net`** is wired in **Phase 5** by adding a **new** server block to **`ktaxi-nginx`** only — see [docs/GABIA_STAGING_DEPLOY_CHECKLIST.md](../../docs/GABIA_STAGING_DEPLOY_CHECKLIST.md).

## Standalone VPS (dedicated T-Ride server)

If the server has **host** nginx and **no** `ktaxi-nginx`:

```bash
sudo cp deploy/nginx/ttaxi-staging-http.conf /etc/nginx/sites-available/tride-staging
sudo ln -sf /etc/nginx/sites-available/tride-staging /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
```

After TLS: switch to `ttaxi-staging.conf`.

| File | Purpose |
|------|---------|
| `ttaxi-staging-http.conf` | Port 80 only — initial smoke |
| `ttaxi-staging.conf` | HTTP→HTTPS + TLS |

Both configs:

- Serve Flutter from `root` with SPA fallback (`try_files … /index.html`)
- Proxy `/api/` → backend (e.g. `127.0.0.1:3000` or PM2)
- Proxy `/socket.io/` → backend (optional for MVP)

See [docs/MVP_DEPLOYMENT_PREP.md](../../docs/MVP_DEPLOYMENT_PREP.md) for env/CORS alignment.
