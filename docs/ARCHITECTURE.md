# Thailand Airport Transfer Platform — System Architecture (v1.0)

> 설계 문서 | 코드 구현 전 단계 | 다음 단계: DB 상세 설계 (SQL)

---

## 1. 전체 시스템 아키텍처

### 1.1 아키텍처 개요

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         Client Layer (PWA)                              │
│  Flutter Web  →  Riverpod  →  Repository  →  HTTP / Socket.IO Client    │
└───────────────────────────────┬─────────────────────────────────────────┘
                                │
                    HTTPS (REST) + WebSocket (Socket.IO)
                                │
┌───────────────────────────────┴─────────────────────────────────────────┐
│                    Gabia Cloud — Application Layer                      │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐                   │
│  │ Express API  │  │ Socket.IO    │  │ Static Web   │                   │
│  │ (REST/JWT)   │  │ (Chat)       │  │ (Flutter build)│                 │
│  └──────┬───────┘  └──────┬───────┘  └──────────────┘                   │
│         │                 │                                             │
│  ┌──────┴─────────────────┴──────────────────────────────────┐         │
│  │              Service Layer (Business Logic)                 │         │
│  └──────┬──────────────────────────────────────────────────────┘         │
│         │                                                               │
│  ┌──────┴───────┐  ┌────────────┐  ┌─────────────────────────┐         │
│  │ Repository   │  │ Local FS   │  │ External API Adapters   │         │
│  │ (MySQL)      │  │ (Storage)  │  │ Maps / Flights / FCM    │         │
│  └──────┬───────┘  └────────────┘  └─────────────────────────┘         │
└─────────┼───────────────────────────────────────────────────────────────┘
          │
┌─────────┴─────────┐     ┌──────────────────┐     ┌────────────────────┐
│     MySQL         │     │ Local Storage    │     │ External Services  │
│  (Primary DB)     │     │ (→ S3 확장)      │     │ Google / Aviation  │
└───────────────────┘     └──────────────────┘     │ Stack / Firebase FCM │
                                                   └────────────────────┘
```

### 1.2 레이어 책임

| 레이어 | 책임 | 금지 사항 |
|--------|------|-----------|
| **Presentation (UI)** | 화면 렌더링, 사용자 입력, 네비게이션 | API 호출, 가격/차량 계산, JSON 파싱 |
| **Application (Riverpod)** | 상태 조합, UseCase 호출, UI 상태 전달 | Widget 내부 비즈니스 규칙 |
| **Domain** | 엔티티, UseCase, Repository 인터페이스 | Flutter/HTTP 의존 |
| **Data** | Repository 구현, API Client, Model 직렬화 | UI 로직 |
| **Backend Controller** | 요청 검증, 응답 포맷 | SQL 직접 작성, 복잡한 비즈니스 규칙 |
| **Backend Service** | 비즈니스 규칙, 트랜잭션 조율 | HTTP 응답 직접 구성 |
| **Backend Repository** | DB CRUD, 쿼리 | 비즈니스 규칙 |

### 1.3 통신 패턴

| 용도 | 프로토콜 | 인증 |
|------|----------|------|
| 예약, 설정, 관리자 CRUD | REST (JSON) | JWT Bearer |
| 실시간 채팅 | Socket.IO | JWT (handshake) |
| Places Autocomplete | REST (백엔드 프록시 권장) | 서버 API Key |
| 푸시 알림 | FCM (서버 → 디바이스) | FCM Server Key (서버만) |

### 1.4 인증 모델

- **고객**: 예약 시 게스트 + 이메일; 추후 계정 통합 시 `users` 연결
- **기사**: JWT (`role: driver`)
- **관리자**: JWT (`role: admin`)
- **Socket.IO**: 연결 시 JWT 검증 → `roomId` join 권한 검사

### 1.5 스토리지 확장 전략

```
Phase 1: Local Storage (Gabia 서버 디스크)
         storage/uploads/{year}/{month}/{uuid}.ext

Phase 2: Storage Adapter Interface
         IStorageService → LocalStorageService | S3StorageService

Phase 3: S3 호환 Object Storage (Gabia 또는 AWS S3)
         동일 인터페이스, 환경변수로 Provider 전환
```

### 1.6 환경 분리

| 환경 | Frontend | Backend | DB |
|------|----------|---------|-----|
| local | localhost:8080 | localhost:3000 | local MySQL |
| staging | staging.ttaxi.com | api-staging | staging DB |
| production | ttaxi.com | api.ttaxi.com | production DB |

환경 변수는 `.env` + `flutter_dotenv` / `dotenv`로만 관리. 키는 코드·Git에 포함하지 않음.

---

## 2. Flutter 폴더 구조

**원칙**: Feature First + Clean Architecture (Presentation / Application / Domain / Data)

```
lib/
├── main.dart                          # 앱 진입점, ProviderScope, runApp
│
├── app/                               # 앱 전역 조립 (App 레벨)
│   ├── app.dart                       # MaterialApp.router, 테마, l10n 등록
│   └── bootstrap.dart                 # env 로드, 에러 핸들링, 의존성 초기화
│
├── config/                            # 환경·빌드 설정 (코드에 시크릿 없음)
│   ├── env/
│   │   ├── env.dart                   # abstract Env 인터페이스
│   │   ├── dev_env.dart
│   │   ├── staging_env.dart
│   │   └── prod_env.dart
│   └── app_config.dart                # Env에서 읽은 apiBaseUrl, socketUrl 등
│
├── core/                              # 앱 전역 공통 (Feature에 속하지 않는 기반)
│   ├── constants/
│   │   ├── api_constants.dart         # path prefix만 (URL 아님)
│   │   ├── app_constants.dart         # 앱 이름, 기본 locale 등
│   │   ├── storage_keys.dart          # SharedPreferences 키
│   │   └── vehicle_constants.dart     # 차량 타입 enum 매핑 (UI용)
│   ├── errors/
│   │   ├── exceptions.dart            # ServerException, NetworkException
│   │   └── failures.dart              # Failure 타입 (Either 패턴용)
│   ├── network/
│   │   ├── api_client.dart            # Dio/http 래퍼, 인터셉터
│   │   ├── auth_interceptor.dart      # JWT 헤더 주입
│   │   └── socket_client.dart         # Socket.IO 래퍼
│   ├── storage/
│   │   ├── local_storage.dart         # SharedPreferences / secure storage
│   │   └── token_storage.dart         # access/refresh token
│   ├── utils/
│   │   ├── date_formatter.dart
│   │   ├── validators.dart
│   │   └── logger.dart
│   └── extensions/
│       ├── context_extensions.dart
│       └── string_extensions.dart
│
├── theme/                             # 디자인 시스템
│   ├── app_theme.dart
│   ├── app_colors.dart
│   ├── app_text_styles.dart
│   └── app_spacing.dart
│
├── localization/                      # 다국어 (아래 6절 상세)
│   ├── l10n.yaml                      # codegen 설정
│   ├── app_en.arb
│   ├── app_ko.arb
│   ├── app_th.arb
│   ├── app_ja.arb
│   ├── app_zh.arb
│   └── l10n_extensions.dart           # context.l10n 헬퍼
│
├── routes/                            # GoRouter 중앙 관리
│   ├── app_router.dart                # GoRouter 인스턴스
│   ├── route_paths.dart               # 경로 상수 (/booking, /admin 등)
│   └── route_guards.dart              # 인증·역할 기반 redirect
│
├── shared/                            # 2개 이상 Feature가 쓰는 UI·Provider
│   ├── widgets/
│   │   ├── app_scaffold.dart
│   │   ├── language_selector.dart
│   │   ├── loading_overlay.dart
│   │   ├── error_view.dart
│   │   ├── counter_row.dart
│   │   └── place_search_field.dart
│   └── providers/
│       └── locale_provider.dart
│
└── features/                          # Feature First — 기능 단위 모듈
    │
    ├── auth/                          # 로그인·JWT (기사/관리자)
    │   ├── data/
    │   │   ├── models/                # login_request_model, token_model
    │   │   ├── datasources/           # auth_remote_datasource
    │   │   └── repositories/          # auth_repository_impl
    │   ├── domain/
    │   │   ├── entities/              # user_entity
    │   │   ├── repositories/          # auth_repository (interface)
    │   │   └── usecases/              # login_usecase, logout_usecase
    │   └── presentation/
    │       ├── providers/             # auth_provider (Riverpod)
    │       ├── screens/
    │       └── widgets/
    │
    ├── home/                          # 메인·서비스 유형 선택
    │   ├── domain/
    │   ├── data/
    │   └── presentation/
    │       ├── screens/               # home_screen
    │       └── widgets/               # service_type_card
    │
    ├── booking/                       # 예약 플로우 (핵심)
    │   ├── domain/
    │   │   ├── entities/
    │   │   │   ├── booking_draft_entity.dart
    │   │   │   ├── passenger_entity.dart
    │   │   │   └── luggage_entity.dart
    │   │   ├── repositories/
    │   │   └── usecases/
    │   │       ├── recommend_vehicle_usecase.dart
    │   │       ├── calculate_price_usecase.dart
    │   │       └── create_reservation_usecase.dart
    │   ├── data/
    │   │   ├── models/                # json_serializable + freezed
    │   │   ├── datasources/
    │   │   └── repositories/
    │   └── presentation/
    │       ├── providers/             # booking_flow_notifier
    │       ├── screens/
    │       │   ├── passenger_luggage_screen.dart
    │       │   ├── route_detail_screen.dart   # pickup/dropoff/city/golf 분기
    │       │   ├── vehicle_select_screen.dart
    │       │   ├── booking_confirm_screen.dart
    │       │   └── booking_complete_screen.dart
    │       └── widgets/
    │
    ├── flight/                        # AviationStack 연동 (픽업 전용)
    │   ├── domain/ / data/ / presentation/
    │
    ├── places/                        # Google Places (백엔드 프록시)
    │   ├── domain/ / data/ / presentation/
    │
    ├── chat/                          # Socket.IO 채팅
    │   ├── domain/
    │   │   ├── entities/              # message_entity, chat_room_entity
    │   │   └── repositories/
    │   ├── data/
    │   │   ├── datasources/           # chat_socket_datasource
    │   │   └── repositories/
    │   └── presentation/
    │       ├── providers/             # chat_notifier
    │       ├── screens/
    │       └── widgets/               # chat_bubble, chat_input
    │
    ├── reservation/                   # 예약 조회 (고객·기사)
    │   └── ...
    │
    ├── admin/                         # 관리자 패널
    │   ├── dashboard/
    │   ├── reservations/
    │   ├── chats/
    │   ├── drivers/
    │   ├── pricing/
    │   ├── golf_courses/
    │   ├── airports/
    │   ├── notifications/
    │   ├── translations/
    │   └── settings/
    │       └── (각 서브 feature 또는 admin/presentation/tabs 구조)
    │
    ├── driver/                        # 기사 앱 화면 (향후 네이티브 공유)
    │   └── ...
    │
    └── pwa/                           # PWA 설치 유도, FCM 토큰 등록
        └── presentation/
            └── widgets/               # install_banner, notification_handler
```

### 2.1 폴더 역할 요약

| 폴더 | 역할 |
|------|------|
| `app/` | 앱 부트스트랩, `MaterialApp.router` 조립 |
| `config/` | 환경별 URL·설정 (시크릿 없음) |
| `core/` | Feature 무관 공통 인프라 (네트워크, 에러, 스토리지) |
| `theme/` | 색·타이포·간격 일원화 |
| `localization/` | ARB 기반 공식 l10n |
| `routes/` | GoRouter 경로·가드 |
| `shared/` | Feature 간 공유 Widget/Provider |
| `features/*` | 기능 단위 독립 모듈 (Clean Architecture 3층) |
| `features/*/domain` | 순수 Dart — Entity, UseCase, Repository 인터페이스 |
| `features/*/data` | API·DB·Model, Repository 구현 |
| `features/*/presentation` | Screen, Widget, Riverpod Notifier/Provider |

### 2.2 Feature 내부 의존 방향

```
presentation → domain (usecase)
data → domain (repository interface 구현)
presentation ↛ data (직접 호출 금지)
```

---

## 3. Backend 폴더 구조

**원칙**: Controller → Service → Repository → MySQL | 외부 API는 Adapter로 분리

```
backend/
├── src/
│   ├── index.js                       # HTTP + Socket 서버 부트
│   ├── app.js                         # Express 앱 조립 (미들웨어, routes)
│   │
│   ├── config/
│   │   ├── database.js                # MySQL pool
│   │   ├── socket.js                  # Socket.IO 설정
│   │   ├── storage.js                 # Local / S3 adapter 선택
│   │   └── firebase.js                # FCM 초기화
│   │
│   ├── constants/
│   │   ├── roles.js                   # customer, driver, admin
│   │   ├── reservation_status.js
│   │   ├── service_types.js
│   │   ├── vehicle_types.js
│   │   └── error_codes.js
│   │
│   ├── middlewares/
│   │   ├── auth.middleware.js         # JWT 검증
│   │   ├── role.middleware.js         # role 기반 접근
│   │   ├── validate.middleware.js     # Joi/Zod 스키마 검증
│   │   ├── error.middleware.js        # 전역 에러 핸들러
│   │   └── rate_limit.middleware.js
│   │
│   ├── routes/
│   │   ├── index.js                   # /api 마운트
│   │   ├── auth.routes.js
│   │   ├── reservation.routes.js
│   │   ├── vehicle.routes.js
│   │   ├── flight.routes.js
│   │   ├── places.routes.js
│   │   ├── chat.routes.js             # REST: 히스토리 조회
│   │   ├── notification.routes.js
│   │   ├── admin.routes.js
│   │   └── public.routes.js           # airports, golf-courses (인증 불필요)
│   │
│   ├── controllers/
│   │   ├── auth.controller.js
│   │   ├── reservation.controller.js
│   │   ├── vehicle.controller.js
│   │   ├── flight.controller.js
│   │   ├── places.controller.js
│   │   ├── chat.controller.js
│   │   ├── notification.controller.js
│   │   └── admin/
│   │       ├── dashboard.controller.js
│   │       ├── driver.controller.js
│   │       ├── pricing.controller.js
│   │       └── ...
│   │
│   ├── services/
│   │   ├── auth.service.js
│   │   ├── reservation.service.js     # 예약 생성, 번호 생성, 상태 전이
│   │   ├── vehicle.service.js         # 차량 추천 로직 (PRD 규칙)
│   │   ├── pricing.service.js
│   │   ├── flight.service.js
│   │   ├── places.service.js
│   │   ├── chat.service.js
│   │   ├── notification.service.js    # FCM 발송
│   │   ├── storage.service.js         # 파일 업로드 (추후)
│   │   └── admin/
│   │       └── dashboard.service.js
│   │
│   ├── repositories/
│   │   ├── user.repository.js
│   │   ├── driver.repository.js
│   │   ├── reservation.repository.js
│   │   ├── passenger.repository.js
│   │   ├── luggage.repository.js
│   │   ├── vehicle.repository.js
│   │   ├── vehicle_price.repository.js
│   │   ├── golf_course.repository.js
│   │   ├── airport.repository.js
│   │   ├── chat_room.repository.js
│   │   ├── chat_message.repository.js
│   │   ├── notification.repository.js
│   │   ├── setting.repository.js
│   │   └── translation.repository.js
│   │
│   ├── models/                        # DB row → 도메인 객체 매핑 (선택)
│   │   └── ...
│   │
│   ├── validators/
│   │   ├── reservation.validator.js
│   │   ├── auth.validator.js
│   │   └── ...
│   │
│   ├── adapters/                      # 외부 API (키는 config/env만)
│   │   ├── google_places.adapter.js
│   │   ├── aviation_stack.adapter.js
│   │   └── fcm.adapter.js
│   │
│   ├── storage/
│   │   ├── storage.interface.js
│   │   ├── local.storage.js
│   │   └── s3.storage.js              # Phase 2
│   │
│   ├── socket/
│   │   ├── index.js                   # Socket.IO attach
│   │   ├── chat.handler.js            # join_room, send_message
│   │   └── auth.middleware.js         # socket JWT
│   │
│   └── utils/
│       ├── api_response.js            # { success, data, error } 통일
│       ├── date.util.js
│       ├── reservation_number.util.js # TXYYYYMMDD0001
│       └── logger.js
│
├── tests/                             # 추후 Jest
│   ├── unit/
│   └── integration/
│
├── uploads/                           # Local storage (gitignore)
├── .env.example
├── package.json
└── README.md
```

### 3.1 Backend 폴더 역할

| 폴더 | 역할 |
|------|------|
| `config/` | DB, Socket, Storage, Firebase 연결 설정 |
| `constants/` | 매직 스트링·enum 값 중앙 관리 |
| `middlewares/` | 인증, 검증, 에러, Rate limit |
| `routes/` | URL → Controller 매핑만 |
| `controllers` | req/res, Service 호출, HTTP 상태 코드 |
| `services` | **모든 비즈니스 로직** (차량 추천, 가격, 상태 전이) |
| `repositories` | SQL만 (비즈니스 규칙 없음) |
| `adapters` | Google, AviationStack, FCM — 교체·모킹 용이 |
| `storage/` | 파일 저장 추상화 (Local → S3) |
| `socket/` | 실시간 채팅 이벤트 |
| `validators/` | 요청 body/query 스키마 |

---

## 4. Database 테이블 목록

> SQL은 다음 단계에서 작성. 여기서는 테이블·역할·관계만 정의.

### 4.1 사용자·인증

| 테이블 | 역할 |
|--------|------|
| **users** | 고객·기사·관리자 통합 계정. email, role, FCM token, 국가·연락처 |
| **user_sessions** | (선택) refresh token, 디바이스 정보, 만료 — JWT 갱신용 |

### 4.2 기사·차량

| 테이블 | 역할 |
|--------|------|
| **drivers** | 기사 프로필, 차량 타입, 가용 상태, users FK |
| **vehicles** | 차량 **타입** 마스터 (SEDAN/SUV/VIP_SUV/VAN, 정원·수하물 한도) |
| **vehicle_prices** | 서비스 유형 × 차량 타입별 기본 요금 (THB) |

### 4.3 예약 (핵심)

| 테이블 | 역할 |
|--------|------|
| **reservations** | 예약 본문: 번호, 서비스 유형, 상태, 경로(Place ID·주소), 공항·항공, 일시, 골프, 차량·가격, 고객 스냅샷, driver FK |
| **reservation_passengers** | 예약 1건당 성인·어린이 수 |
| **reservation_luggage** | 20"/24"+ 캐리어, 골프백, 특수 수하물 텍스트 |
| **reservation_vehicles** | (다중 차량 배정 시) 예약 1건에 N대 — 타입·대수·단가 |
| **reservation_status_logs** | (선택) 상태 변경 이력 — 감사·알림 트리거 |

### 4.4 마스터 데이터

| 테이블 | 역할 |
|--------|------|
| **airports** | BKK, DMK 등 공항 코드·이름·도시 |
| **golf_courses** | 골프장명, 지역, Place ID, 주소 |

### 4.5 채팅

| 테이블 | 역할 |
|--------|------|
| **chat_rooms** | 예약 1건 = 1 room (`room_TX...`) |
| **chat_messages** | 메시지 본문, sender role/id, 읽음, 시각 |
| **chat_participants** | (선택) room별 참여자·마지막 읽음 시각 |

> PRD의 `messages`는 **`chat_messages`**로 명확히 분리 권장.

### 4.6 알림·설정·다국어

| 테이블 | 역할 |
|--------|------|
| **notifications** | 앱 내 알림 + FCM 발송 여부, user/reservation FK |
| **settings** | key-value (피켓 가격, 회사명, 지원 연락처) |
| **translations** | (선택) DB 기반 동적 번역 — 관리자 UI용. 정적 UI는 Flutter ARB |

### 4.7 스토리지 (추후)

| 테이블 | 역할 |
|--------|------|
| **files** | 업로드 메타: path/url, mime, size, storage_provider (local/s3), uploader |

### 4.8 관계 요약

```
users 1──N reservations (고객)
users 1──1 drivers
drivers 1──N reservations (배정)
reservations 1──1 reservation_passengers
reservations 1──1 reservation_luggage
reservations 1──N reservation_vehicles
reservations 1──1 chat_rooms
chat_rooms 1──N chat_messages
golf_courses ── reservations (nullable FK)
airports ── (코드 문자열 또는 FK)
```

---

## 5. API Endpoint 목록

**Base URL**: `https://api.ttaxi.com/api`  
**인증**: `Authorization: Bearer <JWT>` (🌐 = Public)

### 5.1 Auth

| Method | Endpoint | 설명 | 인증 |
|--------|----------|------|------|
| POST | `/auth/login` | 이메일/비밀번호 로그인 | 🌐 |
| POST | `/auth/register` | 고객 회원가입 (선택) | 🌐 |
| POST | `/auth/refresh` | refresh token 갱신 | 🌐 |
| POST | `/auth/logout` | 세션 무효화 | JWT |
| GET | `/auth/me` | 현재 사용자 정보 | JWT |

### 5.2 Public / Reference Data

| Method | Endpoint | 설명 |
|--------|----------|------|
| GET | `/airports` | 공항 목록 |
| GET | `/golf-courses` | 골프장 목록 (`?region=`) |
| GET | `/golf-regions` | 골프 지역 enum 목록 |
| GET | `/vehicles/types` | 차량 타입 마스터 |
| GET | `/vehicles/prices` | 요금 (`?serviceType=`) |

### 5.3 Vehicle & Pricing (계산)

| Method | Endpoint | 설명 |
|--------|----------|------|
| POST | `/vehicles/recommend` | 인원·수하물 → 추천 차량·선택 가능 목록 |
| POST | `/pricing/calculate` | 선택 차량·옵션 → 총액 |

### 5.4 Places (Google 프록시)

| Method | Endpoint | 설명 |
|--------|----------|------|
| GET | `/places/autocomplete` | `?input=&language=` |
| GET | `/places/details` | `?placeId=&language=` |

### 5.5 Flight (AviationStack 프록시)

| Method | Endpoint | 설명 |
|--------|----------|------|
| GET | `/flights` | `?flightNumber=&date=` |

### 5.6 Reservations

| Method | Endpoint | 설명 | 인증 |
|--------|----------|------|------|
| POST | `/reservations` | 예약 생성 (+ 채팅방 자동 생성) | 🌐 또는 JWT |
| GET | `/reservations` | 목록 (필터: status, date) | JWT |
| GET | `/reservations/:reservationNumber` | 상세 조회 | JWT / 게스트 토큰 |
| PATCH | `/reservations/:id/status` | 상태 변경 | admin |
| PATCH | `/reservations/:id/driver` | 기사 배정 | admin |
| PATCH | `/reservations/:id/price` | 골프 등 수동 가격 | admin |
| POST | `/reservations/:id/cancel` | 취소 | customer/admin |

### 5.7 Chat (REST — 히스토리·관리)

| Method | Endpoint | 설명 |
|--------|----------|------|
| GET | `/chat/rooms` | 활성 채팅방 목록 (admin) |
| GET | `/chat/rooms/:roomId` | room 메타 |
| GET | `/chat/rooms/:roomId/messages` | 메시지 히스토리 |
| POST | `/chat/rooms/:roomId/read` | 읽음 처리 |

### 5.8 Chat (Socket.IO Events)

| Event | Direction | 설명 |
|-------|-----------|------|
| `join_room` | C→S | roomId, role, name |
| `message_history` | S→C | 과거 메시지 |
| `send_message` | C→S | 텍스트 전송 |
| `new_message` | S→C | 브로드캐스트 |
| `mark_read` | C→S | 읽음 |
| `messages_read` | S→C | 읽음 상태 동기화 |

### 5.9 Notifications

| Method | Endpoint | 설명 |
|--------|----------|------|
| GET | `/notifications` | 내 알림 목록 |
| PATCH | `/notifications/:id/read` | 읽음 |
| POST | `/notifications/fcm-token` | FCM 토큰 등록 |

### 5.10 Admin

| Method | Endpoint | 설명 |
|--------|----------|------|
| GET | `/admin/dashboard` | 대시보드 통계 |
| GET | `/admin/reservations` | 전체 예약 |
| CRUD | `/admin/drivers` | 기사 관리 |
| CRUD | `/admin/vehicle-prices` | 요금 관리 |
| CRUD | `/admin/golf-courses` | 골프장 |
| CRUD | `/admin/airports` | 공항 |
| GET/PUT | `/admin/settings` | 설정 |
| CRUD | `/admin/translations` | DB 번역 (선택) |

### 5.11 Driver (기사 앱)

| Method | Endpoint | 설명 |
|--------|----------|------|
| GET | `/driver/assignments` | 나에게 배정된 예약 |
| PATCH | `/driver/assignments/:id/accept` | 수락 |
| PATCH | `/driver/assignments/:id/complete` | 완료 |
| PATCH | `/driver/availability` | 가용 상태 토글 |

### 5.12 Health

| Method | Endpoint | 설명 |
|--------|----------|------|
| GET | `/health` | 서버 상태 |

### 5.13 응답 형식 (권장)

```json
{ "success": true, "data": { ... }, "meta": { ... } }
{ "success": false, "error": { "code": "...", "message": "..." } }
```

---

## 6. 추천 패키지

### 6.1 Flutter

| 패키지 | 용도 |
|--------|------|
| **flutter_riverpod** + **riverpod_annotation** | 상태관리·DI |
| **go_router** | declarative routing, deep link |
| **dio** | HTTP, 인터셉터, cancel |
| **freezed** + **json_serializable** | immutable Model, JSON |
| **socket_io_client** | Socket.IO |
| **flutter_localizations** + **intl** | 공식 l10n |
| **flutter_dotenv** | env (빌드 시 --dart-define 병행 권장) |
| **shared_preferences** | locale, 비중요 설정 |
| **flutter_secure_storage** | JWT 저장 |
| **equatable** | Entity 비교 (freezed 대안/보조) |
| **logger** | 구조화 로그 |
| **connectivity_plus** | 네트워크 상태 (선택) |
| **firebase_messaging** | FCM (PWA 제한 시 web 전용 전략 별도) |

**Dev**: `build_runner`, `riverpod_generator`, `flutter_lints`, `mocktail`

### 6.2 Backend (Node.js)

| 패키지 | 용도 |
|--------|------|
| **express** | HTTP |
| **socket.io** | WebSocket |
| **mysql2** | MySQL (promise pool) |
| **jsonwebtoken** | JWT |
| **bcryptjs** | 비밀번호 |
| **joi** 또는 **zod** | 요청 검증 |
| **dotenv** | 환경 변수 |
| **cors** | CORS |
| **helmet** | 보안 헤더 |
| **express-rate-limit** | Rate limit |
| **axios** | 외부 API |
| **firebase-admin** | FCM |
| **winston** | 로깅 |
| **multer** | 파일 업로드 (local) |
| **@aws-sdk/client-s3** | S3 확장 시 |

**Dev**: `jest`, `supertest`, `nodemon`

---

## 7. 상태관리 — Riverpod 추천

### 7.1 왜 Riverpod?

| 이유 | 설명 |
|------|------|
| **Compile-safe** | Provider보다 ref 타입·의존성 오류를 빌드 타임에 발견 |
| **테스트 용이** | ProviderScope override로 Repository·UseCase 모킹 |
| **Clean Architecture 적합** | `Repository Provider` → `UseCase Provider` → `Notifier` 계층 분리 |
| **코드 생성** | `@riverpod`로 Notifier/AsyncNotifier 자동 생성 → 초보자 실수 감소 |
| **AsyncValue** | API loading/error/data UI 패턴 표준화 |
| **전역 없이 DI** | GetIt 없이도 의존성 주입 가능 |
| **Flutter Web/PWA** | 단일 codebase, isolate 없이도 충분 |

### 7.2 Riverpod 사용 패턴 (권장)

```
apiClientProvider          → core
authRepositoryProvider     → features/auth/data
recommendVehicleUseCaseProvider → features/booking/domain
bookingFlowNotifierProvider   → features/booking/presentation
```

- **UI**: `ConsumerWidget` / `HookConsumerWidget`
- **일회성 액션**: `ref.read(notifier).submit()`
- **화면 상태**: `AsyncNotifier` + `AsyncValue.when`

Bloc/Cubit도 가능하지만, DI·Provider 조합·학습 곡선을 고려하면 **초보 + Cursor AI 조합에는 Riverpod이 문서·생성기 품질이 좋음**.

---

## 8. 라우팅 — GoRouter

### 8.1 경로 설계

| Path | 화면 | Guard |
|------|------|-------|
| `/` | Home | - |
| `/booking/:serviceType` | 예약 플로우 (nested) | - |
| `/booking/:serviceType/passengers` | 인원·수하물 | - |
| `/booking/:serviceType/route` | 경로·일시 | - |
| `/booking/:serviceType/vehicle` | 차량 선택 | - |
| `/booking/:serviceType/confirm` | 확인·고객정보 | - |
| `/booking/complete/:reservationNumber` | 완료 | - |
| `/reservation/:reservationNumber` | 예약 상세 | - |
| `/chat/:roomId` | 채팅 | JWT optional |
| `/login` | 로그인 | - |
| `/admin` | Admin Shell | admin |
| `/admin/dashboard` | 대시보드 | admin |
| `/admin/reservations` | 예약 | admin |
| `/admin/chats` | 채팅 | admin |
| `/admin/drivers` | 기사 | admin |
| `/driver` | 기사 홈 | driver |

### 8.2 ShellRoute

- `AdminShell`: NavigationRail + child
- `BookingShell`: Step indicator + child

### 8.3 Deep Link

- 예약 완료: `/booking/complete/TX202607010001`
- 채팅: `/chat/room_TX202607010001`

---

## 9. 다국어 (Localization)

### 9.1 전략: 이중 트랙

| 계층 | 방식 | 용도 |
|------|------|------|
| **정적 UI** | Flutter ARB (`app_ko.arb` 등) | 버튼, 라벨, 화면 텍스트 — **주력** |
| **동적 콘텐츠** | DB `translations` + API | 관리자가 수정하는 문구 (선택) |

### 9.2 ARB 파일

```
localization/
  app_en.arb    # template (@locale en)
  app_ko.arb
  app_th.arb
  app_ja.arb
  app_zh.arb
```

### 9.3 키 규칙

```
feature_screen_element
예: booking_vehicle_select_title
    admin_dashboard_today_revenue
```

### 9.4 언어 추가 절차

1. `app_xx.arb` 추가
2. `l10n.yaml` supported locales 업데이트
3. `MaterialApp` `supportedLocales` 추가
4. `LanguageSelector`에 locale 한 줄 추가

### 9.5 기본 locale

- 저장: `SharedPreferences` + `localeProvider`
- 기본값: `ko` (한국 관광객 UX 우선) 또는 시스템 locale

---

## 10. 프로젝트 개발 순서

| Phase | 작업 | 산출물 |
|-------|------|--------|
| **0** | GitHub repo, env 템플릿, ARCHITECTURE 확정 | docs, .env.example |
| **1** | **DB 상세 설계 + schema.sql + seed** | migrations |
| **2** | Backend: config, middleware, auth JWT | 로그인 API |
| **3** | Backend: 마스터 (airports, vehicles, prices) | Public API |
| **4** | Backend: vehicle recommend + pricing service | 계산 API |
| **5** | Backend: reservation CRUD + chat_room 자동 생성 | 예약 API |
| **6** | Backend: Socket.IO chat + JWT | 실시간 채팅 |
| **7** | Backend: Places/Flight adapters | 프록시 API |
| **8** | Flutter: core, theme, routes, l10n, Riverpod | 앱骨架 |
| **9** | Flutter: home + booking flow (4 service types) | 고객 예약 E2E |
| **10** | Flutter: chat feature | 채팅 UI |
| **11** | Flutter: admin feature | 관리자 |
| **12** | PWA: manifest, service worker, install banner | PWA |
| **13** | FCM: token 등록 + notification service | 푸시 |
| **14** | Driver API + 화면 (또는 기사용 route) | 기사 배정 |
| **15** | Gabia 배포, HTTPS, CI (GitHub Actions) | production |
| **16** | Storage adapter + files (선택) | 파일 업로드 |

**초보 개발자 권장**: Phase 1→5→8→9를 먼저 완료하면 **데모 가능한 MVP**.

---

## 11. 확장성을 고려한 설계 방향

### 11.1 단기 (0–6개월)

- Feature First로 **booking / chat / admin** 독립 유지
- API versioning 준비: `/api/v1/...`
- Repository 인터페이스로 DB·API 교체 가능

### 11.2 중기 (6–12개월)

- **Flutter 모바일** (Android/iOS): `features/*` domain·data 재사용, presentation만 platform 분기
- **기사 네이티브 앱**: 동일 backend, `driver` feature 확장
- **S3 Storage**: `IStorageService` 스위치만 변경
- **Redis**: Socket room presence, session cache (선택)

### 11.3 장기 (1년+)

- **다국가/다공항** 확장: `airports`, `vehicle_prices` region 컬럼
- **결제** (Stripe/Thai PG): `payments`, `payment_transactions` 테이블 추가
- **멀티 테넌티** (화이트라벨): `organizations` 테이블
- **Read Replica**: reservation 조회 API만 replica 연결
- **이벤트 기반**: reservation 상태 변경 → queue → FCM/이메일

### 11.4 Cursor AI 활용 팁 (초보 개발자)

1. **한 Feature씩** Cursor에 요청 (`features/booking/domain`만 먼저)
2. **UseCase 단위**로 테스트·구현 요청
3. `ARCHITECTURE.md` + 해당 feature 폴더를 @컨텍스트에 항상 포함
4. UI에 비즈니스 로직 넣지 말라고 매번 명시
5. API 변경 시 `docs/API.md`와 validators 동시 업데이트

---

## 다음 단계: DB 상세 설계

다음 문서에서 진행할 항목:

1. 각 테이블 **컬럼 목록** (타입, NULL, DEFAULT)
2. **인덱스** (reservation_number, status, pickup_date, room_id)
3. **FK·ON DELETE** 정책
4. **ENUM** 값 정의
5. **seed data** 범위
6. **schema.sql** + migration 전략 (수동 vs knex/prisma)

---

*Document version: 1.0 | Last updated: 2026-06-26*
