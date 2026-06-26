# OpenAPI / Swagger UI

## File

- **Spec**: `openapi.yaml` (OpenAPI 3.1.0)
- **Aligned with**: API Contract v1.0, Database Design v1.1

## Swagger UI (local)

### Option 1 — Swagger Editor (online)

1. Open https://editor.swagger.io/
2. File → Import URL or paste `openapi.yaml` contents
3. Preview docs and try requests (with mock server)

### Option 2 — Docker

```bash
docker run -p 8081:8080 -e SWAGGER_JSON=/openapi.yaml -v "%CD%":/openapi swaggerapi/swagger-ui
```

Then open http://localhost:8081

### Option 3 — npx (no install)

```bash
cd docs/openapi
npx @redocly/cli preview-docs openapi.yaml
```

## Authentication in Swagger UI

1. Call `POST /auth/login` or `/auth/register`
2. Copy `accessToken` from response `data`
3. Click **Authorize** → enter: `Bearer <accessToken>`

## Code generation (later)

- Flutter: `openapi_generator` or manual models from schemas
- Node.js: `openapi-typescript` or Joi schemas from contract
