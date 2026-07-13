# T-Ride Production Proxy

This folder is a template for a new production VPS only. It must not be used on
the existing KTaxi/TTaxi server and must not modify legacy nginx, certbot,
legacy domains, legacy paths, or existing host 80/443 listeners.

## Recommended topology

- Customer: `https://ride.example.com/`
- Booking lookup: `https://ride.example.com/booking/lookup`
- Driver: `https://ride.example.com/driver`
- Admin: `https://ride.example.com/admin`
- API: `https://ride.example.com/api`
- Socket.IO: `https://ride.example.com/socket.io`

Caddy terminates TLS for the single domain, proxies `/api` and `/socket.io` to
`tride-prod-backend:3000`, and sends all other routes to
`tride-prod-frontend:80`. Flutter web history routing stays inside the frontend
container nginx fallback.

## Required production env alignment

Use the real domain only on the production server:

```env
APP_ENV=production
NODE_ENV=production
API_BASE_URL=/api
TRIDE_API_BASE_URL=/api
SOCKET_URL=https://ride.example.com
ALLOWED_ORIGINS=https://ride.example.com
CORS_ORIGIN=https://ride.example.com
FRONTEND_PUBLIC_URL=https://ride.example.com
BACKEND_PUBLIC_URL=https://ride.example.com
PUBLIC_API_URL=https://ride.example.com/api
```

## Network

The app compose and proxy compose share the external Docker network
`tride-prod-net`. Create and start the app stack only during an approved
production deployment window; this template does not authorize deployment.

## TLS

Caddy manages ACME certificates and automatic renewal. Before first use, point
DNS for the real production domain to the new VPS and copy `.env.example` to
`.env` with production-only values.

Do not issue certificates, change DNS, or start containers from this repository
review alone.
