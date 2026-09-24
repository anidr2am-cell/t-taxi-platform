# Admin Manual QA (local only)

This folder is **not** part of production builds. Use it to verify admin manual call UI against fake data only.

## Start mock API

```bash
node frontend/qa/mock_admin_api_server.mjs
```

- Listens on `http://127.0.0.1:3099`
- No production JWT/DB; token `qa-mock-admin-token` from mock login only
- Virtual bookings `TX202609240001` (edit/fixture), `TX202609240003` (assign API conflict with driver **199**)
- After changing `mock_admin_api_server.mjs`, restart the mock process (port **3099** must not be an old instance)

## Run QA web app

```bash
cd frontend
flutter build web -t lib/qa/admin_manual_qa_main.dart \
  --dart-define=API_BASE_URL=http://127.0.0.1:3099 \
  --dart-define=APP_ENV=development

npx http-server build/web -p 8088 -c-1
```

Open `http://127.0.0.1:8088` — menu links to create/edit (admin-themed shell) and dispatch detail assign flows (success on TX202609240001; driver **199** list-eligible but assign API 409 on TX202609240003).

## Commit vs local

| Path | Commit? | Notes |
|------|---------|--------|
| `lib/qa/admin_manual_qa_main.dart` | Optional | Separate entry; not used by `lib/main.dart` |
| `qa/mock_admin_api_server.mjs` | Optional | Local fixture server |
| `qa/README.md` | Optional | This file |
| `qa/screenshots/` | **No** | Local verification artifacts |

## Inspection helpers

- `GET http://127.0.0.1:3099/api/v1/qa/last-manual-patch`
- `GET http://127.0.0.1:3099/api/v1/qa/last-assign`
