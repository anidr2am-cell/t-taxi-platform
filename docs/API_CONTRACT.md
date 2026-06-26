# TTaxi Platform — REST API Contract (v1.0)

> **기준**: Database Design v1.1 · Architecture v1.0  
> **단계**: API Contract (구현·SQL 미작성)  
> **Base URL**: `https://api.ttaxi.com/api/v1` (local: `http://localhost:3000/api/v1`)  
> **Content-Type**: `application/json` (파일 업로드: `multipart/form-data`)

---

## 0. Global Conventions

### 0.1 Authentication

| 항목 | 규칙 |
|------|------|
| Header | `Authorization: Bearer <access_token>` |
| Guest | 예약 생성·조회(예약번호+이메일)는 토큰 없이 허용 가능 (설정으로 제어) |
| Role | `CUSTOMER`, `DRIVER`, `ADMIN`, `SUPER_ADMIN` |

### 0.2 Response Envelope

**성공**

```json
{
  "success": true,
  "message": "OK",
  "data": { }
}
```

**실패**

```json
{
  "success": false,
  "error_code": "VALIDATION_ERROR",
  "message": "Human readable message",
  "errors": [ { "field": "email", "message": "Invalid email" } ]
}
```

**페이지네이션** (`data` 내부 또는 `data` 자체)

```json
{
  "page": 1,
  "page_size": 20,
  "total": 150,
  "items": [ ]
}
```

### 0.3 Common HTTP Status

| Status | 사용 |
|--------|------|
| 200 | 조회·수정 성공 |
| 201 | 생성 성공 |
| 204 | 삭제 성공 (body 없음) |
| 400 | Validation / 비즈니스 규칙 위반 |
| 401 | 인증 필요·토큰 만료 |
| 403 | Role 권한 없음 |
| 404 | 리소스 없음 |
| 409 | 상태 전이 불가·중복 |
| 422 | 도메인 규칙 (차량 선택 불가 등) |
| 500 | 서버 오류 |

### 0.4 Common Error Codes

| error_code | 설명 |
|------------|------|
| `AUTH_REQUIRED` | 토큰 없음 |
| `AUTH_INVALID` | 토큰 무효 |
| `FORBIDDEN` | Role 불일치 |
| `NOT_FOUND` | 리소스 없음 |
| `VALIDATION_ERROR` | 입력 검증 실패 |
| `INVALID_STATUS_TRANSITION` | 예약 상태 전이 불가 |
| `VEHICLE_NOT_SELECTABLE` | 추천 이하 차량 선택 |
| `DRIVER_NOT_AVAILABLE` | 기사 배정 불가 |
| `BOOKING_NOT_ACCESSIBLE` | 예약 접근 권한 없음 |
| `RATE_LIMIT` | 요청 제한 |
| `EXTERNAL_API_ERROR` | Google / AviationStack 등 |
| `INTERNAL_ERROR` | 서버 오류 |

### 0.5 Naming

- JSON 필드: **camelCase**
- Enum 값: **UPPER_SNAKE** (DB·API·Flutter 동일)
- 날짜: ISO 8601 `2026-07-01T14:30:00+07:00`
- 금액: `number` (DECIMAL), 통화 `currency` 별도 필드

### 0.6 Shared DTOs (참조)

```json
// BookingStatus
"PENDING" | "CONFIRMED" | "DRIVER_ASSIGNED" | "DRIVER_ARRIVED" | "PICKED_UP" | "COMPLETED" | "CANCELLED" | "NO_SHOW"

// ServiceTypeCode
"AIRPORT_PICKUP" | "AIRPORT_DROPOFF" | "CITY_TRANSFER" | "GOLF_TRANSFER"

// VehicleTypeCode
"SEDAN" | "SUV" | "VIP_SUV" | "VAN" | "VIP_VAN" | "LUXURY"

// PaymentStatus
"UNPAID" | "PENDING" | "PAID" | "REFUNDED" | "FAILED"

// ChargeType
"VEHICLE_BASE" | "NAME_SIGN" | "NIGHT_SURCHARGE" | "AIRPORT_PARKING" | "TOLL_GATE" | "PROMOTION" | "COUPON" | "DRIVER_EXTRA" | "SEASON_SURCHARGE" | "HOLIDAY_SURCHARGE" | "OTHER"
```

---

## 1. Authentication

### 1.1 POST `/auth/register`

| 항목 | 값 |
|------|-----|
| Description | 고객 회원가입 |
| Auth | No |
| Role | PUBLIC |

**Request Body**

```json
{
  "email": "user@example.com",
  "password": "string (min 8)",
  "name": "string",
  "phone": "+66123456789",
  "countryCode": "TH",
  "locale": "ko"
}
```

**Response 201**

```json
{
  "success": true,
  "message": "Registered",
  "data": {
    "user": { "id": 1, "email": "...", "role": "CUSTOMER", "name": "..." },
    "accessToken": "jwt...",
    "refreshToken": "jwt...",
    "expiresIn": 3600
  }
}
```

**Validation**: email 형식, password ≥ 8, phone 필수  
**Errors**: 400 `VALIDATION_ERROR`, 409 email 중복

---

### 1.2 POST `/auth/login`

| 항목 | 값 |
|------|-----|
| Description | 로그인 (Customer / Driver / Admin) |
| Auth | No |
| Role | PUBLIC |

**Request Body**

```json
{
  "email": "string",
  "password": "string"
}
```

**Response 200**: 1.1과 동일 구조

**Errors**: 401 `AUTH_INVALID`

---

### 1.3 POST `/auth/refresh`

| Auth | No (refresh token body) |

**Request Body**

```json
{ "refreshToken": "string" }
```

**Response 200**: accessToken, expiresIn

---

### 1.4 POST `/auth/logout`

| Auth | Yes |
| Role | ANY |

**Request Body**

```json
{ "refreshToken": "string" }
```

**Response 200**: success true

---

### 1.5 GET `/auth/me`

| Auth | Yes |
| Role | ANY |

**Response 200**

```json
{
  "data": {
    "id": 1,
    "email": "...",
    "role": "CUSTOMER",
    "name": "...",
    "phone": "...",
    "locale": "ko",
    "driverProfile": null
  }
}
```

---

### 1.6 POST `/auth/driver/login`

| Description | 기사 전용 로그인 (별도 endpoint — Driver 앱) |
| Auth | No |

Request/Response: `/auth/login` 동일, `role` must be `DRIVER`

---

## 2. Customer

### 2.1 GET `/customer/profile`

| Auth | Yes | Role | CUSTOMER |

**Response 200**: user + userProfile

---

### 2.2 PATCH `/customer/profile`

**Request Body**

```json
{
  "name": "string",
  "phone": "string",
  "locale": "ko",
  "marketingOptIn": true
}
```

---

### 2.3 GET `/customer/bookings`

| Auth | Yes | Role | CUSTOMER |

**Query**: `page`, `page_size`, `status`, `fromDate`, `toDate`

**Response 200**: pagination + `items[]` (BookingSummary)

---

### 2.4 POST `/customer/fcm-token`

**Request Body**

```json
{
  "fcmToken": "string",
  "platform": "WEB",
  "deviceId": "string"
}
```

---

## 3. Booking

### 3.1 POST `/bookings/vehicle/recommend`

| Description | 인원·수하물 기반 차량 추천 |
| Auth | No (또는 Optional) |
| Role | PUBLIC |

**Request Body**

```json
{
  "adults": 2,
  "children": 0,
  "infants": 0,
  "carriers20Inch": 1,
  "carriers24InchPlus": 0,
  "golfBags": 0
}
```

**Response 200**

```json
{
  "data": {
    "recommendedVehicleType": "SUV",
    "vehicleCount": 1,
    "multiVehicle": false,
    "assignments": [ { "vehicleType": "SUV", "count": 1 } ],
    "selectableVehicleTypes": ["SUV", "VIP_SUV", "VAN"]
  }
}
```

**Validation**: adults ≥ 1  
**Errors**: 400

---

### 3.2 POST `/bookings/pricing/calculate`

| Description | 요금 계산 (charge items 미리보기) |
| Auth | No |

**Request Body**

```json
{
  "serviceTypeCode": "AIRPORT_PICKUP",
  "vehicleTypeCode": "SUV",
  "vehicleCount": 1,
  "scheduledPickupAt": "2026-07-01T14:00:00+07:00",
  "originAirportIata": "BKK",
  "destinationRegion": "Pattaya",
  "options": {
    "nameSign": true
  },
  "passengers": { "adults": 2, "children": 0 },
  "luggage": { "carriers20Inch": 1, "carriers24InchPlus": 0, "golfBags": 0 }
}
```

**Response 200**

```json
{
  "data": {
    "currency": "THB",
    "chargeItems": [
      {
        "chargeType": "VEHICLE_BASE",
        "description": "SUV Airport Pickup",
        "quantity": 1,
        "unitPrice": 1500,
        "amount": 1500
      },
      {
        "chargeType": "NAME_SIGN",
        "description": "Name sign service",
        "quantity": 1,
        "unitPrice": 100,
        "amount": 100
      }
    ],
    "totalAmount": 1600,
    "appliedPricingRuleId": 12
  }
}
```

**Errors**: 422 `VEHICLE_NOT_SELECTABLE`

---

### 3.3 POST `/bookings`

| Description | 예약 생성 (+ 채팅방·charge items·activity log 자동) |
| Auth | Optional (회원: JWT, 게스트: 없음) |
| Role | PUBLIC / CUSTOMER |

**Request Body**

```json
{
  "serviceTypeCode": "AIRPORT_PICKUP",
  "scheduledPickupAt": "2026-07-01T14:00:00+07:00",
  "origin": {
    "address": "Suvarnabhumi Airport",
    "placeId": "ChIJ...",
    "lat": 13.69,
    "lng": 100.75
  },
  "destination": {
    "address": "Centric Sea Pattaya",
    "placeId": "ChIJ...",
    "lat": 12.93,
    "lng": 100.88
  },
  "transfer": {
    "airportIata": "BKK",
    "flightNumber": "KE651",
    "flightScheduledArrivalAt": "2026-07-01T13:30:00+07:00",
    "flightEstimatedArrivalAt": "2026-07-01T13:45:00+07:00",
    "delayMinutes": 15,
    "golfCourseId": null,
    "golfRegion": null,
    "driverIncluded": false,
    "pickupTimeLocal": null
  },
  "passengers": { "adults": 2, "children": 0, "infants": 0 },
  "luggage": {
    "carriers20Inch": 1,
    "carriers24InchPlus": 0,
    "golfBags": 0,
    "specialItems": "stroller"
  },
  "vehicleTypeCode": "SUV",
  "vehicleCount": 1,
  "options": { "nameSign": true },
  "customer": {
    "name": "Kim",
    "email": "kim@example.com",
    "phone": "+821012345678",
    "countryCode": "KR"
  },
  "specialRequests": "Child seat",
  "guestAccessToken": null
}
```

**Response 201**

```json
{
  "data": {
    "bookingNumber": "TX202607010001",
    "id": 1001,
    "status": "PENDING",
    "paymentStatus": "UNPAID",
    "totalAmount": 1600,
    "currency": "THB",
    "chargeItems": [ ... ],
    "chatRoomCode": "room_TX202607010001",
    "guestAccessToken": "opaque-token-for-guest-chat"
  }
}
```

**Validation**
- serviceTypeCode enum
- customer.name, email, phone 필수
- vehicleTypeCode ∈ selectableVehicleTypes
- transfer 필드: serviceType에 따라 조건부 필수

**Errors**: 400, 422

---

### 3.4 GET `/bookings/{bookingNumber}`

| Path | `bookingNumber` e.g. TX202607010001 |
| Auth | Yes **또는** Guest (`email` + `guestAccessToken` query) |
| Role | CUSTOMER (own), DRIVER (assigned), ADMIN |

**Query (Guest)**: `email`, `guestAccessToken`

**Response 200**: BookingDetail (§3.12)

**Errors**: 403 `BOOKING_NOT_ACCESSIBLE`, 404

---

### 3.5 GET `/bookings`

| Description | 예약 리스트 (Admin/Driver/Customer scope) |
| Auth | Yes |
| Role | ADMIN, DRIVER, CUSTOMER |

**Query**

| Param | 설명 |
|-------|------|
| `page`, `page_size` | 페이지네이션 |
| `status` | 단일 또는 comma-separated |
| `serviceTypeCode` | |
| `fromDate`, `toDate` | scheduledPickupAt 범위 |
| `customerEmail` | Admin only |
| `driverId` | Admin |
| `search` | Admin: bookingNumber, name, phone |

**Response 200**: pagination + BookingSummary[]

---

### 3.6 PATCH `/bookings/{bookingNumber}`

| Description | 예약 수정 (제한 필드) |
| Auth | Yes |
| Role | ADMIN, CUSTOMER (PENDING only) |

**Request Body** (허용 필드만)

```json
{
  "scheduledPickupAt": "2026-07-01T15:00:00+07:00",
  "specialRequests": "string",
  "destination": { "address": "...", "placeId": "..." }
}
```

**Response 200**: BookingDetail  
**Errors**: 409 if status not editable

---

### 3.7 POST `/bookings/{bookingNumber}/cancel`

| Auth | Yes |
| Role | CUSTOMER (own, 제한 상태), ADMIN |

**Request Body**

```json
{
  "reason": "CANCEL_BY_CUSTOMER",
  "memo": "Flight cancelled"
}
```

**Response 200**: status → CANCELLED

---

### 3.8 PATCH `/bookings/{bookingNumber}/status`

| Description | 상태 변경 (State Machine 준수) |
| Auth | Yes |
| Role | ADMIN, DRIVER (제한 전이) |

**Request Body**

```json
{
  "status": "CONFIRMED",
  "reason": "PAYMENT_CONFIRMED",
  "memo": "optional"
}
```

**Response 200**: BookingDetail  
**Errors**: 409 `INVALID_STATUS_TRANSITION`

---

### 3.9 GET `/bookings/{bookingNumber}/charges`

| Description | 요금 라인 아이템 조회 |
| Auth | Yes |
| Role | CUSTOMER (own), DRIVER, ADMIN |

**Response 200**

```json
{
  "data": {
    "chargeItems": [ ... ],
    "totalAmount": 1600,
    "currency": "THB"
  }
}
```

---

### 3.10 POST `/bookings/{bookingNumber}/charges`

| Description | 추가 요금 라인 (Admin) |
| Auth | Yes |
| Role | ADMIN |

**Request Body**

```json
{
  "chargeType": "TOLL_GATE",
  "description": "Highway toll",
  "quantity": 1,
  "unitPrice": 80
}
```

**Response 201**: charge item + updated totalAmount

---

### 3.11 GET `/bookings/{bookingNumber}/activity-logs`

| Auth | Yes | Role | ADMIN |

**Response 200**: activity log list

---

### 3.12 GET `/bookings/{bookingNumber}/status-logs`

| Auth | Yes | Role | ADMIN, CUSTOMER (own) |

---

### 3.13 BookingDetail Schema (공통)

```json
{
  "id": 1001,
  "bookingNumber": "TX202607010001",
  "status": "PENDING",
  "paymentStatus": "UNPAID",
  "serviceTypeCode": "AIRPORT_PICKUP",
  "scheduledPickupAt": "2026-07-01T14:00:00+07:00",
  "origin": { "address": "...", "placeId": "...", "lat": 0, "lng": 0 },
  "destination": { ... },
  "transfer": {
    "airportIata": "BKK",
    "flightNumber": "KE651",
    "flightScheduledArrivalAt": "...",
    "flightEstimatedArrivalAt": "...",
    "delayMinutes": 15,
    "delayStatus": "Delayed 15 min"
  },
  "passengers": { "adults": 2, "children": 0, "infants": 0 },
  "luggage": { ... },
  "vehicleTypeCode": "SUV",
  "recommendedVehicleTypeCode": "SUV",
  "vehicleCount": 1,
  "chargeItems": [ ... ],
  "totalAmount": 1600,
  "currency": "THB",
  "customer": { "name": "...", "email": "...", "phone": "...", "countryCode": "KR" },
  "driver": { "id": 5, "name": "...", "phone": "..." },
  "specialRequests": "...",
  "chatRoomCode": "room_TX202607010001",
  "createdAt": "...",
  "updatedAt": "..."
}
```

---

## 4. Booking Status State Machine

### 4.1 상태 정의

| Status | 설명 |
|--------|------|
| `PENDING` | 생성 직후, 확인 전 |
| `CONFIRMED` | 예약 확정 (결제 대기/완료 포함 운영 정책) |
| `DRIVER_ASSIGNED` | 기사 배정 완료 |
| `DRIVER_ARRIVED` | 기사 현장 도착 |
| `PICKED_UP` | 픽업 완료 (승차) |
| `COMPLETED` | 서비스 완료 |
| `CANCELLED` | 취소 |
| `NO_SHOW` | 고객 노쇼 |

### 4.2 허용 전이 (Happy Path)

```
PENDING
  → CONFIRMED
  → DRIVER_ASSIGNED
  → DRIVER_ARRIVED
  → PICKED_UP
  → COMPLETED
```

### 4.3 전이 매트릭스

| From | To | Actor | 비고 |
|------|-----|-------|------|
| PENDING | CONFIRMED | ADMIN | |
| PENDING | CANCELLED | CUSTOMER, ADMIN | |
| CONFIRMED | DRIVER_ASSIGNED | ADMIN | 기사 배정 API 병행 |
| CONFIRMED | CANCELLED | CUSTOMER, ADMIN | |
| DRIVER_ASSIGNED | DRIVER_ARRIVED | DRIVER, ADMIN | |
| DRIVER_ASSIGNED | CANCELLED | ADMIN | |
| DRIVER_ASSIGNED | CONFIRMED | ADMIN | 재배정 전 해제 시 |
| DRIVER_ARRIVED | PICKED_UP | DRIVER, ADMIN | |
| PICKED_UP | COMPLETED | DRIVER, ADMIN | |
| PENDING | NO_SHOW | ADMIN | 픽업 예정 후 |
| CONFIRMED | NO_SHOW | ADMIN | |
| DRIVER_ASSIGNED | NO_SHOW | ADMIN | |
| DRIVER_ARRIVED | NO_SHOW | ADMIN | |
| * | CANCELLED | ADMIN | SUPER_ADMIN 항상 (제한 완화 가능) |

**금지**: `COMPLETED`, `CANCELLED`, `NO_SHOW` → 다른 상태 (재오픈은 Admin SUPER_ADMIN만 별도 API)

### 4.4 API 처리

- `PATCH /bookings/{bookingNumber}/status` 호출 시 Service Layer가 매트릭스 검증
- 실패 시 `409 INVALID_STATUS_TRANSITION`
- 성공 시 `booking_status_logs` + `booking_activity_logs` 기록

---

## 5. Booking Number Generation (API)

### 5.1 규칙

| 항목 | 값 |
|------|-----|
| 형식 | `TX` + `YYYYMMDD` + `0001` (4자리 zero-pad) |
| 예시 | `TX202607010001` |
| 저장 | `bookings.booking_number` UNIQUE |
| PK | `bookings.id` (BIGINT) — API 내부·FK용 |

### 5.2 생성 시점·주체

1. **클라이언트는 예약번호를 생성하지 않음**
2. `POST /bookings` 처리 중 **서버 단일 트랜잭션**:
   - `booking_number_sequences`에서 당일 `date_prefix` row `FOR UPDATE`
   - 없으면 INSERT, `last_sequence` + 1
   - `TX` + date_prefix + pad4(seq) 조합
   - `bookings` INSERT
   - `chat_rooms.room_code` = `room_{bookingNumber}`
3. 동시 요청 시 DB lock으로 중복 방지

### 5.3 API 응답

- 생성 응답에 `bookingNumber` 포함
- 이후 모든 Customer-facing URL은 `bookingNumber` 사용
- Admin 내부 PATCH는 `id` 또는 `bookingNumber` 모두 지원 가능 (contract: **bookingNumber 권장**)

---

## 6. Driver

### 6.1 POST `/driver/online`

| Auth | Yes | Role | DRIVER |

**Request Body**

```json
{ "isOnline": true }
```

**Response 200**: driver status updated (`isOnline`, `lastSeenAt`)

---

### 6.2 POST `/driver/offline`

| Auth | Yes | Role | DRIVER |

**Request Body**

```json
{ "isOnline": false }
```

---

### 6.3 POST `/driver/location`

| Description | 위치 전송 (heartbeat 권장 10~30s) |
| Auth | Yes | Role | DRIVER |

**Request Body**

```json
{
  "lat": 13.7563,
  "lng": 100.5018,
  "heading": 90,
  "speed": 40
}
```

**Response 200**

---

### 6.4 GET `/driver/assignments`

| Auth | Yes | Role | DRIVER |

**Query**: `status` (active), `page`, `page_size`

**Response 200**: assignments where `isActive=true`

---

### 6.5 POST `/driver/assignments/{assignmentId}/accept`

| Auth | Yes | Role | DRIVER |

**Response 200**: assignment status → ACCEPTED

---

### 6.6 POST `/driver/assignments/{assignmentId}/reject`

**Request Body**

```json
{ "reason": "string" }
```

**Response 200**: assignment → REJECTED, Admin 재배정 필요

---

### 6.7 POST `/driver/bookings/{bookingNumber}/arrived`

| Description | DRIVER_ARRIVED 상태 전이 |
| Role | DRIVER |

---

### 6.8 POST `/driver/bookings/{bookingNumber}/picked-up`

| Description | PICKED_UP 상태 전이 |
| Role | DRIVER |

---

### 6.9 POST `/driver/bookings/{bookingNumber}/complete`

| Description | COMPLETED 상태 전이 |
| Role | DRIVER |

---

## 7. Vehicle

### 7.1 GET `/vehicles/types`

| Auth | No |
| Role | PUBLIC |

**Response 200**

```json
{
  "data": [
    {
      "code": "SEDAN",
      "name": "Sedan",
      "maxPassengers": 2,
      "maxLuggage": 4,
      "isActive": true
    }
  ]
}
```

---

### 7.2 GET `/vehicles/prices`

| Auth | No |

**Query**: `serviceTypeCode`

**Response 200**: vehicle_type × base_price list (fallback prices)

---

### 7.3 GET `/admin/vehicle-price-rules` — see Admin §10

---

## 8. Airport

### 8.1 GET `/airports`

| Auth | No |
| Role | PUBLIC |

**Query**: `isActive` (default true), `countryCode`

**Response 200**

```json
{
  "data": [
    {
      "id": 1,
      "iataCode": "BKK",
      "icaoCode": "VTBS",
      "name": "Suvarnabhumi Airport",
      "city": "Bangkok",
      "countryCode": "TH",
      "timezone": "Asia/Bangkok",
      "isActive": true
    }
  ]
}
```

---

### 8.2 GET `/airports/{iataCode}`

| Path | iataCode e.g. BKK |

---

## 9. Golf Course

### 9.1 GET `/golf-courses`

| Auth | No |

**Query**: `region`, `isActive`, `page`, `page_size`

**Response 200**

```json
{
  "data": {
    "items": [
      {
        "id": 1,
        "region": "Pattaya",
        "name": "Siam Country Club",
        "address": "...",
        "placeId": "...",
        "lat": 0,
        "lng": 0,
        "phone": "...",
        "website": "https://...",
        "isActive": true
      }
    ],
    "page": 1,
    "page_size": 20,
    "total": 8
  }
}
```

---

### 9.2 GET `/golf-regions`

| Auth | No |

**Response 200**: `["Bangkok", "Pattaya", ...]`

---

## 10. Chat (REST — 실시간은 WebSocket 병행)

### 10.1 GET `/chat/rooms/{roomCode}`

| Path | roomCode e.g. room_TX202607010001 |
| Auth | Yes or Guest token |
| Role | CUSTOMER, DRIVER, ADMIN |

**Response 200**

```json
{
  "data": {
    "roomCode": "room_TX202607010001",
    "bookingNumber": "TX202607010001",
    "participants": [ ... ],
    "isActive": true
  }
}
```

---

### 10.2 POST `/chat/rooms`

| Description | 예약 생성 시 자동 생성 — 수동 호출은 Admin/복구용 |
| Auth | Yes | Role | ADMIN |

**Request Body**

```json
{ "bookingNumber": "TX202607010001" }
```

**Response 201**

---

### 10.3 GET `/chat/rooms/{roomCode}/messages`

| Auth | Yes |

**Query**: `page`, `page_size`, `beforeId` (cursor)

**Response 200**

```json
{
  "data": {
    "items": [
      {
        "id": 1,
        "senderRole": "CUSTOMER",
        "senderName": "Kim",
        "messageType": "TEXT",
        "content": "Hello",
        "messageStatus": "READ",
        "replyMessageId": null,
        "attachments": [],
        "createdAt": "..."
      }
    ],
    "page": 1,
    "page_size": 50,
    "total": 10
  }
}
```

---

### 10.4 POST `/chat/rooms/{roomCode}/messages`

| Description | REST fallback 메시지 전송 (WebSocket 우선) |
| Auth | Yes |

**Request Body**

```json
{
  "content": "string",
  "messageType": "TEXT",
  "replyMessageId": null
}
```

**Response 201**: message object

---

### 10.5 POST `/chat/rooms/{roomCode}/read`

| Description | room 내 메시지 읽음 처리 |
| Auth | Yes |

**Request Body**

```json
{
  "lastReadMessageId": 100
}
```

**Response 200**

---

### 10.6 POST `/chat/rooms/{roomCode}/files`

| Description | 채팅 파일 업로드 |
| Auth | Yes |
| Content-Type | multipart/form-data |

**Form Fields**: `file` (binary), `replyMessageId` (optional)

**Response 201**

```json
{
  "data": {
    "messageId": 101,
    "file": {
      "id": 1,
      "fileUrl": "https://...",
      "mimeType": "image/jpeg",
      "fileSize": 102400
    }
  }
}
```

**Validation**: max size (e.g. 10MB), allowed mime types  
**Errors**: 400

---

### 10.7 WebSocket Events (참고 — REST Contract 보조)

| Event | Direction | Payload |
|-------|-----------|---------|
| `join_room` | C→S | roomCode, role, displayName |
| `send_message` | C→S | content, replyMessageId |
| `new_message` | S→C | message object |
| `mark_read` | C→S | lastReadMessageId |
| `message_delivered` | S→C | messageId |

Base: same host, path `/socket.io`, JWT in handshake `auth.token`

---

## 11. Notification

### 11.1 GET `/notifications`

| Auth | Yes | Role | ANY |

**Query**: `page`, `page_size`, `isRead`

**Response 200**: pagination

---

### 11.2 PATCH `/notifications/{id}/read`

| Auth | Yes |

**Response 200**

---

### 11.3 POST `/notifications/fcm-token`

| Description | Customer §2.4와 동일 — alias endpoint |
| Auth | Yes |

---

### 11.4 POST `/admin/notifications/broadcast`

| Description | 공지 Push (Admin) |
| Auth | Yes | Role | ADMIN, SUPER_ADMIN |

**Request Body**

```json
{
  "channel": "PUSH",
  "title": "string",
  "body": "string",
  "targetRole": "CUSTOMER",
  "payload": {}
}
```

---

## 12. Admin

> Role: `ADMIN` 또는 `SUPER_ADMIN` (삭제·설정 변경은 SUPER_ADMIN)

### 12.1 GET `/admin/dashboard`

**Response 200**

```json
{
  "data": {
    "todayBookings": 42,
    "todayRevenue": 65000,
    "pendingBookings": 5,
    "awaitingDriver": 3,
    "activeChats": 12,
    "statusBreakdown": [ { "status": "PENDING", "count": 5 } ]
  }
}
```

---

### 12.2 GET `/admin/bookings`

| Description | 예약 검색·필터 |
| Query | §3.5 + Admin search |

---

### 12.3 PATCH `/admin/bookings/{bookingNumber}`

| Description | Admin 전체 수정 (고객 정보, 일시, 차량 등) |

---

### 12.4 POST `/admin/bookings/{bookingNumber}/assign-driver`

| Description | 기사 배정 (재배정 지원) |

**Request Body**

```json
{
  "driverId": 5,
  "driverVehicleId": 12,
  "assignmentReason": "Nearest available driver"
}
```

**Response 200**

```json
{
  "data": {
    "assignmentId": 88,
    "isActive": true,
    "driver": { ... },
    "bookingStatus": "DRIVER_ASSIGNED"
  }
}
```

**Side effects**: 이전 assignment `isActive=false`, `unassignedAt` 설정

---

### 12.5 POST `/admin/bookings/{bookingNumber}/unassign-driver`

**Request Body**

```json
{ "reason": "Driver emergency" }
```

---

### 12.6 GET/POST `/admin/bookings/{bookingNumber}/notes`

| Description | 관리자 메모 CRUD |

**POST Body**

```json
{
  "note": "VIP customer",
  "isPrivate": true
}
```

---

### 12.7 CRUD `/admin/drivers`

| Method | URL | Description |
|--------|-----|-------------|
| GET | `/admin/drivers` | 목록 |
| POST | `/admin/drivers` | 생성 |
| GET | `/admin/drivers/{id}` | 상세 |
| PATCH | `/admin/drivers/{id}` | 수정 |
| DELETE | `/admin/drivers/{id}` | soft delete |

---

### 12.8 CRUD `/admin/vehicle-prices`

| GET/PATCH | `/admin/vehicle-prices` | fallback 가격 |
| GET/POST/PATCH/DELETE | `/admin/vehicle-price-rules` | 조건부 규칙 |
| POST | `/admin/vehicle-price-rules/{id}/conditions` | 조건 추가 |

**Price Rule Body (POST)**

```json
{
  "serviceTypeCode": "AIRPORT_PICKUP",
  "vehicleTypeCode": "SUV",
  "name": "BKK Night surcharge",
  "basePrice": 1800,
  "priceModifierType": "FIXED",
  "priority": 100,
  "validFrom": "2026-01-01T00:00:00+07:00",
  "validTo": null,
  "conditions": [
    { "conditionType": "ORIGIN_AIRPORT", "operator": "EQ", "conditionValue": "BKK" },
    { "conditionType": "TIME_RANGE", "operator": "BETWEEN", "conditionValue": "22:00-06:00" }
  ]
}
```

---

### 12.9 CRUD `/admin/golf-courses`

| Method | URL |
|--------|-----|
| GET | `/admin/golf-courses` |
| POST | `/admin/golf-courses` |
| PATCH | `/admin/golf-courses/{id}` |
| DELETE | `/admin/golf-courses/{id}` |

---

### 12.10 CRUD `/admin/airports`

동일 CRUD 패턴

---

### 12.11 CRUD `/admin/users`

| GET | `/admin/users` | Role, search filter |
| PATCH | `/admin/users/{id}` | role, isActive |
| POST | `/admin/users` | Admin/Driver 계정 생성 |

---

### 12.12 GET `/admin/chats`

| Description | 활성 채팅방 목록 |

**Response 200**: room list + lastMessage + unreadCount

---

### 12.13 CRUD `/admin/translations`

| GET | `/admin/translations` |
| POST | `/admin/translations` |
| PATCH | `/admin/translations/{keyId}` |

**POST Body**

```json
{
  "keyName": "booking.confirm.title",
  "category": "ui",
  "values": {
    "ko": "예약 확인",
    "en": "Confirm Booking",
    "th": "...",
    "ja": "...",
    "zh": "..."
  }
}
```

---

### 12.14 GET/PUT `/admin/settings`

| GET | `/admin/settings` | group filter |
| PUT | `/admin/settings/{group}/{key}` | value update |

**PUT Body**

```json
{
  "value": "string or number or json",
  "dataType": "STRING"
}
```

---

## 13. Settings (Public / Customer)

### 13.1 GET `/settings/public`

| Auth | No |
| Description | 공개 설정만 (company name, support phone) |

---

## 14. Translation

### 14.1 GET `/translations`

| Auth | No |

**Query**: `locale` (ko), `category` (ui)

**Response 200**

```json
{
  "data": {
    "locale": "ko",
    "items": [
      { "keyName": "app.title", "value": "TTaxi" }
    ]
  }
}
```

---

### 14.2 GET `/translations/bundle`

| Description | Flutter 앱 초기 로드용 전체 번들 |
| Query | `locale` |

---

## 15. External Proxy APIs (Customer/Booking 보조)

### 15.1 GET `/places/autocomplete`

| Auth | No |
| Query | `input`, `language` |

**Response 200**: Google Places predictions (proxied)

---

### 15.2 GET `/places/details`

| Query | `placeId`, `language` |

---

### 15.3 GET `/flights`

| Query | `flightNumber`, `date` (YYYY-MM-DD) |

**Response 200**

```json
{
  "data": {
    "flightNumber": "KE651",
    "scheduledArrivalAt": "...",
    "estimatedArrivalAt": "...",
    "delayMinutes": 15,
    "delayStatus": "Delayed 15 min"
  }
}
```

**Errors**: 503 `EXTERNAL_API_ERROR`

---

## 16. Health

### 16.1 GET `/health`

| Auth | No |

**Response 200**

```json
{
  "success": true,
  "data": { "status": "ok", "version": "1.0.0", "timestamp": "..." }
}
```

---

## 17. Flutter ↔ API ↔ DB Mapping (요약)

| API Field | DB Table.Column |
|-----------|-----------------|
| `bookingNumber` | `bookings.booking_number` |
| `status` | `bookings.status` |
| `chargeItems[]` | `booking_charge_items` |
| `totalAmount` | `bookings.total_amount` |
| `roomCode` | `chat_rooms.room_code` |
| `assignmentId` | `booking_driver_assignments.id` |
| `isActive` (assignment) | `booking_driver_assignments.is_active` |

---

## 18. Versioning & Next Steps

| 단계 | 산출물 |
|------|--------|
| 1 | `database/00~11` SQL (본 contract FK·enum 일치) |
| 2 | Node.js validators (Joi/Zod) — 본 contract Request Body |
| 3 | Flutter models (`freezed` + `json_serializable`) — Response Body |
| 4 | OpenAPI 3.0 export (선택) |

---

*API Contract version: 1.0 | Aligns with Database Design v1.1 | 2026-06-26*
