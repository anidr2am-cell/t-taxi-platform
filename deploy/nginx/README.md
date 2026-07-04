# Nginx — T-Ride staging (HTTP only, first boot before TLS)

Use this when HTTPS certificates are not ready yet. Replace `staging.example.com` and paths, then:

```bash
sudo cp deploy/nginx/ttaxi-staging-http.conf /etc/nginx/sites-available/ttaxi-staging
sudo ln -sf /etc/nginx/sites-available/ttaxi-staging /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
```

After certbot/Let's Encrypt is installed, switch to `ttaxi-staging.conf` (HTTPS + redirect).

| File | Purpose |
|------|---------|
| `ttaxi-staging-http.conf` | Port 80 only — initial smoke test |
| `ttaxi-staging.conf` | HTTP→HTTPS redirect + TLS (production-like staging) |

Both configs:

- Serve Flutter from `root` with SPA fallback (`try_files … /index.html`)
- Proxy `/api/` → `127.0.0.1:3000`
- Proxy `/socket.io/` → backend (optional for MVP)

See [docs/GABIA_STAGING_DEPLOY_CHECKLIST.md](../../docs/GABIA_STAGING_DEPLOY_CHECKLIST.md).
