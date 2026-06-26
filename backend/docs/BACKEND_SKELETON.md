# TTaxi Backend — Project Skeleton

> Node.js 22 · Express · Clean Architecture · Repository Pattern  
> **현재 단계**: 구조만 완성. API·Repository·SQL 미구현 (Health + Swagger만 동작)

---

## 1. 빠른 시작

```bash
cd backend
cp .env.example .env
# .env 에 DB_USER, DB_NAME, JWT secrets 확인

npm install
npm run dev
```

| URL | 설명 |
|-----|------|
| http://localhost:3000/api/v1/health | 헬스체크 |
| http://localhost:3000/api-docs | Swagger UI (OpenAPI 3.1) |
| http://localhost:3000/api-docs/openapi.json | OpenAPI JSON |

---

## 2. 폴더 구조와 역할

```
backend/
├── src/
│   ├── server.js          # 진입점: HTTP + Socket.IO 시작
│   ├── app.js             # Express 앱 조립 (미들웨어, 라우트)
│   ├── config/            # 환경변수, DB, Swagger, Multer, Firebase
│   ├── routes/            # URL → Controller 연결 (얇은 layer)
│   ├── controllers/       # req/res 처리, Service 호출만
│   ├── services/          # ★ 비즈니스 로직 (상태전이, 가격, 번호생성)
│   ├── repositories/      # ★ SQL / DB only
│   ├── validators/        # Joi 스키마 (OpenAPI Request Body와 일치)
│   ├── models/            # DB row ↔ DTO 매핑 (선택)
│   ├── middlewares/       # auth, role, validate, error
│   ├── socket/            # Socket.IO handlers
│   ├── utils/             # logger, apiResponse, AppError
│   ├── constants/         # enum 문자열 (DB·API·Flutter 동일)
│   ├── helpers/           # DI container
│   ├── events/            # booking.created 등 내부 이벤트
│   ├── jobs/              # cron / 배치 (추후)
│   ├── locales/           # 서버 메시지 i18n
│   └── types/             # JSDoc typedef
├── docs/                  # 백엔드 전용 문서 (이 파일)
├── tests/                 # 테스트
├── uploads/               # 로컬 파일 (gitignore)
├── logs/                  # Winston 로그 (gitignore)
├── .env.example
└── package.json
```

### 요청 처리 흐름 (구현 시)

```
Client
  → routes/booking.routes.js
  → middlewares (auth, validate)
  → controllers/booking.controller.js   ← HTTP만
  → services/booking.service.js         ← 비즈니스 규칙
  → repositories/booking.repository.js  ← SQL
  → MySQL
```

**금지**: Controller에서 SQL, 가격 계산, 상태 전이 로직 작성

---

## 3. 주요 파일 설명

### `server.js`

- `dotenv` 로드
- `http.createServer(app)` + Socket.IO attach
- `SIGTERM` graceful shutdown
- unhandledRejection / uncaughtException 로깅

### `app.js`

- `helmet`, `cors`, `express.json`
- Swagger UI (`config/swagger.js`)
- `/api/v1` 라우트 마운트
- **404** → **error middleware** (순서 중요)

### `config/env.js`

- Joi로 `.env` 검증 — 잘못된 설정은 **시작 시 즉시 실패**
- 다른 파일은 `process.env` 직접 사용 금지 → `config` 사용

### `utils/logger.js`

- Winston: `logs/combined.log`, `logs/error.log` + console
- `logger.info('msg', { meta })`

### `utils/AppError.js` + `middlewares/error.middleware.js`

- 운영 에러: `throw new AppError('...', { statusCode, errorCode })`
- 응답 형식: `{ success: false, error_code, message, errors? }`

### `middlewares/validate.middleware.js`

```js
validate({ body: createBookingSchema })
```

### `helpers/container.js`

- Service/Repository DI — `container.register('bookingService', factory)`
- 테스트 시 mock 교체 용이

### `config/swagger.js`

- `docs/openapi/openapi.yaml` 로드 → Swagger UI
- Flutter / Admin / Driver와 **동일 명세**

### `socket/index.js`

- JWT handshake (TODO)
- `handlers/chat.handler.js` — join_room, send_message

---

## 4. 추천 npm 패키지 (package.json에 포함)

| 패키지 | 용도 |
|--------|------|
| express | HTTP 서버 |
| mysql2 | MySQL pool |
| socket.io | WebSocket 채팅 |
| jsonwebtoken | JWT |
| joi | 요청 검증 |
| dotenv | 환경변수 |
| winston | 로깅 |
| helmet | 보안 헤더 |
| cors | CORS |
| multer | 파일 업로드 |
| firebase-admin | FCM 푸시 |
| swagger-ui-express + yaml | API 문서 |
| axios | 외부 API (Google, AviationStack) |

**추후 추가 권장**: `node-cron`, `express-rate-limit`, `bcryptjs`, `ioredis`

---

## 5. 환경변수 (.env.example)

| 그룹 | 변수 | 설명 |
|------|------|------|
| Server | PORT, NODE_ENV, API_VERSION | |
| DB | DB_HOST, DB_USER, DB_PASSWORD, DB_NAME | |
| JWT | JWT_ACCESS_SECRET, JWT_REFRESH_SECRET | 최소 16자 |
| External | GOOGLE_MAPS_API_KEY, AVIATIONSTACK_API_KEY | 서버만 |
| Firebase | FIREBASE_* | FCM |
| Upload | UPLOAD_DIR, UPLOAD_MAX_FILE_SIZE_MB | |
| Swagger | SWAGGER_ENABLED, SWAGGER_ROUTE | |

---

## 6. 다음 구현 순서 (권장)

1. `database/` SQL 마이그레이션
2. `repositories/` — booking, user, driver
3. `services/` — auth, booking (번호 생성, 상태전이)
4. `validators/` — OpenAPI Request Body와 1:1
5. `controllers/` + `routes/` — OpenAPI path 연결
6. `socket/handlers/chat.handler.js` — chatService 연동
7. `events/` — booking.created → notification.service

---

## 7. 관련 문서

| 문서 | 경로 |
|------|------|
| API Contract | `../docs/API_CONTRACT.md` |
| OpenAPI YAML | `../docs/openapi/openapi.yaml` |
| Database v1.1 | `../docs/DATABASE_DESIGN.md` |
| Architecture | `../docs/ARCHITECTURE.md` |
