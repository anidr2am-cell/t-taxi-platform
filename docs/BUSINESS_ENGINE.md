# TTaxi Platform — Business Engine Design (v1.0)

> **단계**: SQL·코드 작성 **전** 비즈니스 로직 설계  
> **기준**: PRD · Architecture · Database v1.1 · API Contract · OpenAPI 3.1 · Backend Skeleton  
> **원칙**: 비즈니스 로직은 **Service Layer(Engine)** 에만 존재. Controller/UI는 호출만.

---

## 1. 전체 Business Engine Architecture

### 1.1 엔진 맵 (논리 구조)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         Presentation (Flutter / Admin / Driver)              │
└───────────────────────────────────┬─────────────────────────────────────────┘
                                    │ REST / WebSocket
┌───────────────────────────────────▼─────────────────────────────────────────┐
│  Application Layer (Controllers — HTTP only)                                 │
└───────────────────────────────────┬─────────────────────────────────────────┘
                                    │
┌───────────────────────────────────▼─────────────────────────────────────────┐
│  BUSINESS ENGINES (Services)                                                 │
│  ┌──────────────────┐ ┌──────────────────┐ ┌──────────────────────────┐  │
│  │ Vehicle          │ │ Pricing          │ │ Reservation              │  │
│  │ Recommendation   │ │ Engine           │ │ Engine                   │  │
│  └────────┬─────────┘ └────────┬─────────┘ └────────────┬─────────────┘  │
│           │                    │                        │                   │
│  ┌────────┴─────────┐ ┌───────┴────────┐ ┌────────────┴─────────────┐   │
│  │ Driver           │ │ Notification   │ │ Guest / Auth           │   │
│  │ Assignment       │ │ Engine         │ │ Engine                 │   │
│  └──────────────────┘ └────────────────┘ └──────────────────────────┘   │
└───────────────────────────────────┬─────────────────────────────────────────┘
                                    │
┌───────────────────────────────────▼─────────────────────────────────────────┐
│  Domain Events (events/)          Outbox (향후)                              │
│  booking.created · status.changed · driver.assigned · chat.message_sent      │
└───────────────────────────────────┬─────────────────────────────────────────┘
                                    │
┌───────────────────────────────────▼─────────────────────────────────────────┐
│  Repositories (SQL only)  ←  MySQL (rules, bookings, charge_items, …)       │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 1.2 엔진 ↔ Backend Service 매핑 (구현 시)

| Engine | Service (예정) | Repository |
|--------|----------------|------------|
| Vehicle Recommendation | `vehicleRecommendation.service.js` | `vehicleType`, `vehicleCapacityRule` |
| Pricing | `pricing.service.js` | `vehiclePriceRule`, `chargePolicy`, `bookingChargeItem` |
| Reservation | `booking.service.js` | `booking`, `passenger`, `luggage`, `transfer` |
| Booking Number | `bookingNumber.service.js` | `bookingNumberSequence` |
| Guest Access | `guestAccess.service.js` | `booking`, `guestAccessToken` |
| Driver Assignment | `driverAssignment.service.js` | `driver`, `bookingDriverAssignment` |
| Notification | `notification.service.js` | `notification`, `notificationDevice` |
| Status Transition | `bookingStatus.service.js` | `bookingStatusLog` |

### 1.3 호출 원칙

1. **단방향**: Controller → Engine Service → Repository (역방향 금지)
2. **Orchestrator**: `booking.service.js`가 예약 생성 시 Pricing·Number·Chat·Guest·Event를 **순서대로** 호출
3. **규칙은 DB**: Engine은 **규칙 테이블을 읽고 계산**만 수행 (if/else 하드코딩 금지)
4. **결과는 스냅샷**: 계산된 요금은 `booking_charge_items` + `bookings.total_amount`에 **확정 저장**
5. **이벤트 후처리**: 알림·이메일은 `events/` 구독 또는 Outbox로 **비동기** (예약 트랜잭션과 분리)

### 1.4 확장 슬롯 (향후 Tour / Restaurant / Point)

| 슬롯 | 설명 |
|------|------|
| `service_types` | AIRPORT_PICKUP → TOUR_PACKAGE 등 |
| `PricingEngine.calculate(context)` | `serviceType`별 strategy plugin |
| `booking_*_details` | transfer / tour / restaurant 확장 테이블 |
| `charge_type` enum | 새 요금 유형 행 추가만으로 확장 |
| `notification.templates` | 서비스별 템플릿 |

---

## 2. Vehicle Recommendation Engine

### 2.1 목표

입력(인원·수하물) → **DB 규칙** 기반으로  
(1) 최소 필요 차량 조합, (2) 추천 1차 차량 등급, (3) 선택 가능 등급 목록을 반환.

**PRD 초기 규칙은 DB seed로 넣되, 런타임 코드에 상수로 박지 않음.**

### 2.2 DB 규칙 모델 (설계 — SQL은 다음 단계)

#### A. `vehicle_types` (마스터)

차량 등급: SEDAN, SUV, VIP_SUV, VAN, VIP_VAN, LUXURY  
UI 표시명, `sort_order` (등급 순서: SEDAN < SUV < …).

#### B. `vehicle_capacity_rules` ★ 관리자 편집 가능

| 컬럼 (개념) | 설명 |
|-------------|------|
| `vehicle_type_id` | FK |
| `max_passengers` | 최대 인원 (성인+어린이+유아) |
| `max_carriers_20_inch` | 20" 캐리어 최대 |
| `max_carriers_24_inch_plus` | 24"+ 캐리어 최대 |
| `max_golf_bags` | 골프백 최대 |
| `max_special_luggage` | 특수 수하물 개수 (또는 boolean 플래그) |
| `priority` | 다중 차량 배치 시 우선 사용 순서 (VAN=10, SUV=5, SEDAN=1) |
| `is_active` | |

> 한 차량 1행. 관리자 Admin UI에서 수치 변경 → 즉시 추천 결과 변경.

#### C. `vehicle_tier_order` (또는 `vehicle_types.sort_order`)

**선택 가능 차량** = 추천 등급 이상만 허용 (PRD: SUV 추천 시 SEDAN 불가).

### 2.3 입력 정규화

```
totalPassengers = adults + children + infants
L20 = carriers_20_inch
L24 = carriers_24_inch_plus
golf = golf_bags
specialCount = parseSpecialItems(special_luggage)  // 유모차=1, 휠체어=1 등 정책은 settings
```

### 2.4 단일 차량 적합성 (Can Fit?)

활성 `vehicle_capacity_rules` 각 행에 대해:

```
fits(type) =
  totalPassengers <= max_passengers
  AND L20 <= max_carriers_20_inch
  AND L24 <= max_carriers_24_inch_plus
  AND golf <= max_golf_bags
  AND specialCount <= max_special_luggage
```

`fits`가 true인 타입 집합 = **단일 차량 후보**.

### 2.5 단일 차량 추천 (1대로 가능한 경우)

1. `fits` 후보 중 **가장 작은 등급** (`sort_order` 최소) = `recommendedVehicleType` (비용·효율 우선)
2. PRD 예외(24"+ 있으면 SUV 등)는 **capacity_rules 수치**로 표현  
   - 예: SEDAN의 `max_carriers_24_inch_plus = 0` → 24" 1개면 SEDAN 제외

### 2.6 다중 차량 배정 알고리즘 (1대로 불가능한 경우)

**Greedy + Priority (DB `priority` 사용)**

```
remainingP = totalPassengers
remainingL20, remainingL24, remainingGolf, remainingSpecial = 입력값
assignments = []

WHILE remainingP > 0 OR remainingL20 > 0 OR remainingL24 > 0 OR remainingGolf > 0:
  activeTypes = vehicle_types WHERE is_active ORDER BY priority DESC
  FOR type IN activeTypes:
    IF can_assign_partial(type, remaining*):
      assignments.push({ type, count: 1 })
      remaining* -= type capacities (각 항목에서 차감, 음수 방지)
      BREAK inner loop
  IF no type assigned in iteration → ERROR VehicleCapacityExceeded

recommendedVehicleType = highest tier among assignments (max sort_order)
vehicleCount = sum(assignments.count)
```

**예: 9명, 수하물 적음**

- VAN max_passengers=8 → 1대 배정 후 remainingP=1
- 2번째: SUV(3) 또는 SEDAN(2) → 1명이므로 SEDAN 1대  
- 결과: **VAN×1 + SEDAN×1** (PRD "VAN 2대"와 다를 수 있음 — **관리자가 capacity_rules 조정으로 PRD 맞춤**)

**PRD 정합 예 (10명 → VAN 2대)**:

- VAN×2 = 16석 → 10명 충족, 수하물도 16슬롯에 분배 가능하면 **VAN×2만** 반환  
- Greedy는 **priority VAN이 높으면** 10명을 VAN 2대로 먼저 시도

**권장 정책 (설정 `vehicle.multi_assign_strategy`)**:

| 전략 | 설명 |
|------|------|
| `MIN_VEHICLES` | 가능한 최소 대수 (백트래킹, Phase 2) |
| `GREEDY_PRIORITY` | priority 큰 차량부터 반복 (MVP) |
| `COMFORT` | 인원 여유 20% (향후) |

MVP: `GREEDY_PRIORITY` + seed rules를 PRD 예시와 맞게 튜닝.

### 2.7 선택 가능 차량 (Selectable)

```
recommendedIndex = sort_order(recommendedVehicleType)
selectable = all active types WHERE sort_order >= recommendedIndex
```

다중 차량 시: 고객이 **각 슬롯 타입을 올려도** 전체 `assignments` 재검증 (`fits` per slot).

### 2.8 출력 DTO (API: VehicleRecommendationResponse)

```json
{
  "recommendedVehicleType": "SUV",
  "vehicleCount": 1,
  "multiVehicle": false,
  "assignments": [{ "vehicleType": "SUV", "count": 1 }],
  "selectableVehicleTypes": ["SUV", "VIP_SUV", "VAN", ...]
}
```

다중: `multiVehicle: true`, `assignments` 복수 행.

### 2.9 예외 상황

| 상황 | 처리 |
|------|------|
| adults < 1 | `VALIDATION_ERROR` |
| 어떤 조합도 capacity 초과 | `VehicleCapacityExceeded` (422) |
| 활성 vehicle_type 0개 | `VehicleRulesNotConfigured` (500 운영 알림) |
| 특수 수하물 텍스트만 있고 개수 0 | settings `special_luggage.default_count=1` |
| 8명 + 수하물 10개 | 다중 차량 또는 VAN 2대 — rules에 따름 |
| 관리자 rules 변경 후 기존 예약 | **영향 없음** (예약 시점 스냅샷) |

---

## 3. Pricing Engine

### 3.1 목표

컨텍스트(서비스·일시·경로·차량·옵션) → **Charge Item 리스트** + `totalAmount`  
모든 항목은 `booking_charge_items` 행으로 저장 가능한 형태.

### 3.2 요금 구성 (Charge Item 모델)

| charge_type (예) | 설명 | amount 부호 |
|------------------|------|-------------|
| `VEHICLE_BASE` | 차량 기본요금 × 대수 | + |
| `NIGHT_SURCHARGE` | 심야 할증 | + |
| `HOLIDAY_SURCHARGE` | 공휴일 | + |
| `AIRPORT_SURCHARGE` | 공항/피크 | + |
| `TOLL_GATE` | 톨게이트 (실제 또는 예상) | + |
| `WAITING_CHARGE` | 대기 시간 | + |
| `NAME_SIGN` | Meet & Greet (피켓 100 THB) | + |
| `DRIVER_EXTRA` | 기사 추가 요금 | + |
| `PROMOTION` | 프로모션 | − |
| `COUPON` | 쿠폰 | − |
| `SEASON_SURCHARGE` | 시즌 | + |
| `OTHER` | 관리자 수동 | ± |

**총액 = Σ charge_items.amount** (쿠폰·프로모션은 음수 amount)

`bookings.total_amount` = 확정 합계 스냅샷.

### 3.3 DB 규칙 소스 (하드코딩 금지)

| 소스 | 역할 |
|------|------|
| `vehicle_prices` | service × vehicle **fallback** base |
| `vehicle_price_rules` + `conditions` | 조건부 base (요일·시간·공항·지역·시즌) |
| `charge_policies` ★ (신규 설계) | NIGHT/HOLIDAY/AIRPORT 등 **% 또는 fixed** |
| `settings` | NAME_SIGN fixed 100 THB |
| `promotions` / `coupons` | Phase 2 |

#### `charge_policies` (개념)

| 컬럼 | 설명 |
|------|------|
| `charge_type` | NIGHT_SURCHARGE 등 |
| `modifier_type` | FIXED, PERCENT_OF_BASE, PERCENT_OF_SUBTOTAL |
| `modifier_value` | 100 또는 15 (%) |
| `conditions` | TIME_RANGE, IS_HOLIDAY, ORIGIN_AIRPORT … (price_rule와 동일 패턴) |
| `priority`, `valid_from/to`, `is_active` |

### 3.4 계산 순서 (Deterministic Pipeline)

```
Step 0 — Context 수집
  serviceType, scheduledPickupAt, timezone (airport/destination),
  origin/destination, airportIata, region,
  vehicleAssignments[], options (nameSign),
  passengers, memberId (쿠폰/멤버십)

Step 1 — Base Price (per assignment slot)
  FOR each assignment in assignments:
    matchedRule = highest priority vehicle_price_rule WHERE conditions match
    IF none → vehicle_prices fallback
    baseSlot = matchedRule.base_price (or modifier)
  vehicleBaseTotal = SUM(baseSlot × count)
  → ChargeItem: VEHICLE_BASE

Step 2 — Surcharges (정책 테이블 순회, priority 순)
  FOR each active charge_policy WHERE charge_type IN surcharges:
    IF conditions match context:
      amount = applyModifier(policy, vehicleBaseTotal or subtotal)
      → ChargeItem (NIGHT, HOLIDAY, AIRPORT, SEASON, …)

Step 3 — Add-ons (옵션)
  IF options.nameSign → ChargeItem NAME_SIGN (settings.name_sign_price)

Step 4 — Subtotal
  subtotal = SUM(positive items)

Step 5 — Promotions (Phase 2)
  applicable promotions → negative ChargeItems

Step 6 — Coupons (Phase 2)
  validate coupon → negative ChargeItem (max discount cap)

Step 7 — Manual / Post-booking (Admin)
  TOLL, WAITING, DRIVER_EXTRA — 예약 후 추가 가능

Step 8 — Total
  totalAmount = SUM(all charge_items.amount)
  ROUND per currency rule (THB: integer baht, settings)
```

**미리보기 API** (`POST /bookings/pricing/calculate`): Step 0–6까지, DB 저장 없음.  
**예약 생성**: 동일 파이프라인 → `booking_charge_items` INSERT + `bookings.total_amount`.

### 3.5 골프 Transfer 수동 가격

`serviceType = GOLF_TRANSFER` + `admin_price_override` 설정 시:

- Pipeline Step 1–2 **스킵** 또는 override가 `VEHICLE_BASE` 대체  
- Admin 입력 금액 → 단일 `VEHICLE_BASE` 또는 `OTHER` 행

### 3.6 예외

| 상황 | Error |
|------|-------|
| 차량 타입 inactive | `VehicleNotAvailable` |
| price rule 충돌 | priority 최고 1건만 적용 |
| rule 없음 + fallback 없음 | `PricingRuleNotFound` |
| 쿠폰 만료 | `CouponInvalid` |
| 쿠폰 할인 > subtotal | cap to subtotal |

---

## 4. Reservation Engine

### 4.1 상태 모델 (State Machine)

`PENDING → CONFIRMED → DRIVER_ASSIGNED → DRIVER_ARRIVED → PICKED_UP → COMPLETED`  
분기: `CANCELLED`, `NO_SHOW` (API Contract 매트릭스 준수)

**상태 변경 전용**: `bookingStatus.service.js` (전이 검증 + log + event)

### 4.2 예약 생성 파이프라인 (Orchestration)

| Step | 동작 | Service | DB / Side Effect |
|------|------|---------|------------------|
| 1 | 입력 검증 | `validators` + `vehicleRecommendation` (재검증) | — |
| 2 | 가격 계산 | `pricing.service` | — |
| 3 | 트랜잭션 시작 | `booking.service` | — |
| 4 | 예약번호 생성 | `bookingNumber.service` | `booking_number_sequences` lock |
| 5 | Guest token (비회원) | `guestAccess.service` | hash 저장 |
| 6 | `bookings` INSERT | `bookingRepository` | status=PENDING, payment=UNPAID |
| 7 | passengers / luggage / transfer | repositories | 1:1 rows |
| 8 | charge_items INSERT | `pricing.service` persist | N rows |
| 9 | status_log | `bookingStatus.service` | PENDING 기록 |
| 10 | activity_log | `bookingActivity.service` | BOOKING_CREATED |
| 11 | chat_room | `chat.service` | room_TX… + participants |
| 12 | 커밋 | — | — |
| 13 | 이벤트 발행 | `events` | `booking.created` |
| 14 | 알림 (비동기) | `notification.service` | email, admin push |

### 4.3 예약 생성 이후 라이프사이클

| 단계 | 트리거 | Service | 상태 / 효과 |
|------|--------|---------|-------------|
| 관리자 확정 | Admin PATCH status | `bookingStatus` | CONFIRMED |
| 결제 (Phase 2) | Payment webhook | `payment.service` | payment_status=PAID |
| 기사 배정 | Admin assign | `driverAssignment` | DRIVER_ASSIGNED, assignment row |
| 기사 수락 | Driver accept | `driverAssignment` | ACCEPTED |
| 기사 도착 | Driver API | `bookingStatus` | DRIVER_ARRIVED |
| 탑승 | Driver picked-up | `bookingStatus` | PICKED_UP |
| 완료 | Driver complete | `bookingStatus` | COMPLETED |
| 취소 | Customer/Admin | `bookingStatus` | CANCELLED, assignment 해제 |
| 노쇼 | Admin | `bookingStatus` | NO_SHOW |

각 상태 변경: `booking_status_logs` + `booking_activity_logs` + `booking.status_changed` event.

### 4.4 수정·취소 규칙 (비즈니스)

| 상태 | Customer 수정 | Customer 취소 |
|------|---------------|---------------|
| PENDING | 일부 필드 | 허용 |
| CONFIRMED | 제한 | 정책 (settings) |
| DRIVER_ASSIGNED 이후 | 불가 | Admin만 |

수정 시 재가격 필요 필드 변경 → Pricing Engine 재실행 → charge_items 갱신 (감사 log).

### 4.5 리뷰 요청 (Phase 2)

`COMPLETED` 후 `review.service` → notification `REVIEW_REQUEST`  
테이블 `reviews` (향후).

---

## 5. Guest Reservation Flow

### 5.1 Member vs Guest 비교

| 항목 | Guest | Member |
|------|-------|--------|
| 인증 | 없음 | JWT (CUSTOMER) |
| 예약 생성 | `customer_user_id = NULL` | `customer_user_id = user.id` |
| 식별 | `booking_number` + `guest_access_token` | JWT + booking_number |
| 채팅 | token으로 room join | JWT |
| 예약 목록 | 단건 조회만 | `/customer/bookings` |
| FCM | optional email만 | device token 등록 |
| Claim | 회원가입 후 연결 | 불필요 |

### 5.2 Guest 예약 생성

```
1. POST /bookings (no JWT)
2. booking.service:
   - customer 스냅샷 저장 (name, email, phone)
   - guest_access_token = secureRandom(32+) 
   - 저장: guest_token_hash (DB), plain token은 **응답 1회만**
3. Response: bookingNumber, guestAccessToken, chatRoomCode
4. Email: bookingNumber + magic link (?token=&email=)
```

**보안**: DB에는 `SHA-256(token)`만 저장. 조회 시 hash 비교.

### 5.3 Guest 예약 조회 / 채팅

```
GET /bookings/{bookingNumber}?email=&guestAccessToken=
  → guestAccess.service.verify(email, token, bookingNumber)
  → OK: BookingDetail
  → FAIL: BOOKING_NOT_ACCESSIBLE (403)

Socket join_room:
  handshake.auth.guestToken + bookingNumber + email
  → same verify → join chat_participants as CUSTOMER
```

**토큰 만료**: `settings.guest_token_ttl_days` (예: 90일, COMPLETED 후 30일)

### 5.4 Member 예약 생성

```
JWT optional on POST /bookings
IF JWT present:
  customer_user_id = user.id
  customer snapshot from profile (editable in request)
  guest token **생성 안 함**
```

### 5.5 Claim Flow (게스트 → 회원 연결)

```
시나리오: Guest로 예약 후 회원가입

1. POST /auth/register (email, password, …)
2. POST /bookings/claim
   Body: { bookingNumber, guestAccessToken, email }
   Auth: JWT (new member)
3. claim.service:
   - verify guest token + email match booking
   - IF booking.customer_user_id IS NULL:
       UPDATE bookings.customer_user_id = current user
       invalidate guest token (optional)
       activity_log: BOOKING_CLAIMED
   - IF already claimed by other user → DUPLICATE_CLAIM
4. 이후 Member flow로 통합
```

**이메일 일치**: claim 시 `booking.customer_email === user.email` (정규화 lowercase).

### 5.6 Guest → Member 전환 (로그인 상태에서 예약)

이미 로그인한 회원은 처음부터 Member flow — Claim 불필요.

---

## 6. Driver Assignment Engine

### 6.1 MVP: 관리자 수동 배정

```
POST /admin/bookings/{bookingNumber}/assign-driver
  Input: driverId, driverVehicleId?, assignmentReason

1. driverAssignment.service.validate:
   - booking.status IN (CONFIRMED, DRIVER_ASSIGNED) 등 허용 상태
   - driver.is_active, driver.status != SUSPENDED
   - driver vehicle type ≥ booking requirement (rules)
2. IF existing is_active assignment:
   - UPDATE old: is_active=0, unassigned_at, status=CANCELLED
   - activity: DRIVER_UNASSIGNED
3. INSERT booking_driver_assignments (ASSIGNED, is_active=1)
4. UPDATE bookings.driver_id = driverId
5. bookingStatus → DRIVER_ASSIGNED (if not already)
6. event: driver.assigned
7. notification → driver (FCM), customer (push/email)
```

### 6.2 기사 수락 / 거절

| Action | assignment.status | booking.status |
|--------|-------------------|----------------|
| Accept | ACCEPTED | DRIVER_ASSIGNED 유지 |
| Reject | REJECTED | CONFIRMED 복귀, driver_id NULL, Admin 알림 |

### 6.3 향후 자동 배정 (확장 설계)

#### 모드 설정 (`settings.driver_assignment_mode`)

| Mode | 설명 |
|------|------|
| `MANUAL` | MVP — Admin only |
| `AUTO_ON_CONFIRM` | CONFIRMED 시 자동 후보 선정 |
| `AUTO_QUEUE` | 대기열 + 기사 accept timeout |

#### `DriverScoringEngine` (Phase 2)

```
score(driver, booking) =
  w1 * distanceScore(driver.lat/lng, pickup)
  + w2 * onlineScore(driver.is_online)
  + w3 * vehicleMatchScore(driver.vehicle_type, booking.vehicle)
  + w4 * ratingScore(driver.rating_avg)
  + w5 * fairnessScore(-recent_assignment_count)
  + w6 * regionFamiliarityScore (optional)

weights in settings or DB table driver_assignment_weights
```

| 요소 | 데이터 소스 |
|------|-------------|
| 거리 | `drivers.current_lat/lng` vs `bookings.origin` |
| 온라인 | `drivers.is_online`, `last_seen_at` < 2min |
| 차량 | `driver_vehicles.vehicle_type_id` |
| 평점 | `drivers.rating_avg` |
| 배정 공정성 | COUNT assignments today per driver |
| 공항 자격 | driver_airport_certifications (향후) |

#### 자동 배정 플로우

```
CONFIRMED event
  → driverAssignment.autoAssign(bookingId)
  → top N drivers notified (FCM)
  → first ACCEPT within TTL wins
  → else escalate to Admin queue
```

**수동·자동 공통**: 모든 배정은 `booking_driver_assignments` 이력으로 기록.

---

## 7. Notification Engine

### 7.1 아키텍처

```
Domain Event (booking.created, …)
  → notification.service.handle(event)
  → resolve recipients + channels from notification_rules (DB)
  → render template (translations + locale)
  → dispatch:
      Email (SMTP / SendGrid)
      Web Push (FCM web)
      FCM (Android/iOS Driver)
      In-app (notifications table)
      Admin dashboard (websocket / poll)
```

**비동기**: 예약 트랜잭션 커밋 후 `setImmediate` / job queue / outbox.

### 7.2 이벤트 × 수신자 × 채널 매트릭스

| Event | Customer | Driver | Admin | Email | Push/FCM | In-app |
|-------|----------|--------|-------|-------|----------|--------|
| `booking.created` | ✓ 확인 | — | ✓ 대시 | ✓ | ✓ (member) | ✓ |
| `booking.confirmed` | ✓ | — | — | ✓ | ✓ | ✓ |
| `driver.assigned` | ✓ 기사정보 | ✓ 새 배정 | ✓ | ✓ | ✓ | ✓ |
| `driver.unassigned` | ✓ | ✓ | ✓ | optional | ✓ | ✓ |
| `driver.arrived` | ✓ | — | — | optional | ✓ | ✓ |
| `booking.picked_up` | — | — | optional | — | — | ✓ |
| `booking.completed` | ✓ 영수증 | ✓ | ✓ | ✓ | ✓ | ✓ |
| `booking.cancelled` | ✓ | ✓ if assigned | ✓ | ✓ | ✓ | ✓ |
| `booking.no_show` | ✓ | ✓ | ✓ | ✓ | optional | ✓ |
| `chat.message_sent` | ✓ if not sender | ✓ | ✓ monitor | — | ✓ | ✓ |
| `review.request` | ✓ | — | — | ✓ | ✓ | ✓ |
| `payment.failed` | ✓ | — | ✓ | ✓ | ✓ | ✓ |

### 7.3 채널 구현 노트

| 채널 | 구현 |
|------|------|
| Email | `settings` SMTP, template `translations` key `email.booking_created` |
| Web Push (PWA) | `notification_devices` platform=WEB, FCM |
| FCM Driver | platform=ANDROID/IOS |
| Admin | role=ADMIN/SUPER_ADMIN devices + in-app |
| SMS | Phase 2, `NotificationChannel.SMS` |

### 7.4 Guest 알림

- Email: **필수** (예약번호 + guest link)
- Push: guest는 FCM 미등록 → email 우선
- Member 전환 후 과거 booking도 user_id로 in-app 조회

### 7.5 실패 처리

- FCM 실패 → `notifications.status=FAILED`, retry job (3회)
- Email 실패 → log + admin alert
- **예약 본문은 이미 성공** — 알림 실패가 예약 롤백하지 않음

---

## 8. Error Handling Strategy

### 8.1 오류 분류

| 클래스 | HTTP | rollback | 사용자 메시지 |
|--------|------|----------|---------------|
| Validation | 400 | 없음 | 필드별 errors |
| Business (operational) | 403/409/422 | 트랜잭션 롤백 | error_code + message |
| Auth | 401 | 없음 | UNAUTHORIZED |
| Not Found | 404 | 없음 | NOT_FOUND |
| External | 503 | optional | EXTERNAL_API_ERROR |
| System | 500 | 롤백 | INTERNAL_SERVER_ERROR |

### 8.2 비즈니스 오류 카탈로지

| error_code | 발생 Engine | 조건 | 처리 |
|------------|-------------|------|------|
| `VALIDATION_ERROR` | any | Joi 실패 | 400, errors[] |
| `VehicleCapacityExceeded` | Vehicle | 배정 불가 | 422, UI 재입력 |
| `VehicleNotAvailable` | Vehicle/Pricing | inactive type | 422 |
| `VehicleNotSelectable` | Booking | 선택 < 추천 | 422 |
| `PricingRuleNotFound` | Pricing | base 없음 | 422, Admin 알림 |
| `InvalidFlight` | Flight adapter | AviationStack invalid | 400/404 FLIGHT_NOT_FOUND |
| `FlightNotFound` | Flight | 편명 없음 | 404 |
| `GooglePlaceNotFound` | Places | placeId invalid | 404 |
| `GuestTokenExpired` | Guest | TTL 만료 | 403, email 재발송 flow |
| `GuestTokenInvalid` | Guest | hash 불일치 | 403 |
| `BOOKING_NOT_ACCESSIBLE` | Guest/Auth | 권한 없음 | 403 |
| `INVALID_STATUS_TRANSITION` | Status | state machine | 409 |
| `DuplicateBooking` | Booking | idempotency / email race | 409 |
| `DuplicateClaim` | Claim | already has user_id | 409 |
| `DriverNotAvailable` | Assignment | offline/suspended | 409 |
| `DriverVehicleMismatch` | Assignment | 타입 부족 | 422 |
| `CouponInvalid` | Pricing | Phase 2 | 422 |
| `PaymentFailed` | Payment | Phase 2 | 402/422 |
| `EXTERNAL_API_ERROR` | Places/Flight | timeout | 503, retry hint |
| `INTERNAL_SERVER_ERROR` | any | uncaught | 500, log stack |

### 8.3 트랜잭션 경계

| Operation | TX 범위 |
|-----------|---------|
| createBooking | steps 4–12 단일 TX |
| assignDriver | assignment + booking update + status TX |
| addChargeItem | charge insert + total recalc TX |
| sendNotification | **TX 외부** |
| statusChange | status + logs TX |

### 8.4 Idempotency (향후)

`POST /bookings` + `Idempotency-Key` header → duplicate within 24h → same bookingNumber 반환.

---

## 9. Sequence Diagram (텍스트)

### 9.1 Guest 예약 생성

```
Customer(PWA)          API              booking.service    pricing    vehicleRec    DB
    |                    |                    |              |            |         |
    |-- POST /bookings ->|                    |              |            |         |
    |                    |-- create() ------->|              |            |         |
    |                    |                    |-- recommend->|            |         |
    |                    |                    |<- assignments            |         |
    |                    |                    |-- calculate-------------->|         |
    |                    |                    |<- chargeItems[]           |         |
    |                    |                    |-- BEGIN TX ----------------------->|
    |                    |                    |-- gen bookingNumber              |
    |                    |                    |-- gen guestToken                 |
    |                    |                    |-- INSERT booking, passengers...  |
    |                    |                    |-- INSERT charge_items            |
    |                    |                    |-- INSERT chat_room               |
    |                    |                    |-- COMMIT ------------------------>|
    |                    |                    |-- emit booking.created           |
    |                    |<- 201 -------------|              |            |         |
    |<- bookingNumber, guestToken, roomCode ---|              |            |         |

notification.service (async)
    |-- email to customer
    |-- in-app to admin
```

### 9.2 가격 미리보기 (예약 전)

```
Customer -> POST /bookings/pricing/calculate
         -> pricing.service.runPipeline(context)
         -> vehicle_price_rules match
         -> charge_policies match
         -> return chargeItems + total (no DB)
```

### 9.3 관리자 기사 배정

```
Admin -> POST /admin/.../assign-driver
     -> driverAssignment.manualAssign()
     -> deactivate old assignment (if any)
     -> INSERT new assignment (is_active=1)
     -> bookingStatus -> DRIVER_ASSIGNED
     -> emit driver.assigned
     -> notification -> Driver FCM, Customer push
```

### 9.4 Driver 운행 완료

```
Driver -> POST /driver/bookings/{n}/complete
       -> bookingStatus.transition(PICKED_UP -> COMPLETED)  // or from PICKED_UP
       -> assignment.completed_at
       -> emit booking.completed
       -> notification (customer email, review.request scheduled +24h)
```

### 9.5 Guest 채팅

```
Customer -> Socket connect (guestToken, bookingNumber, email)
          -> guestAccess.verify
          -> chat.joinRoom
          -> load message_history

Customer -> send_message
          -> chat.service.saveMessage
          -> broadcast new_message
          -> emit chat.message_sent
          -> notification to Driver + Admin
```

### 9.6 Claim booking after register

```
User -> POST /auth/register
     -> POST /bookings/claim { bookingNumber, guestAccessToken }
     -> guestAccess.verify
     -> UPDATE customer_user_id
     -> activity BOOKING_CLAIMED
```

---

## 10. 향후 확장 가능한 구조

### 10.1 Engine Plugin 패턴

```text
PricingEngine
  ├── strategies/
  │     ├── transferPricing.strategy.js   (MVP)
  │     ├── golfPricing.strategy.js
  │     ├── tourPricing.strategy.js       (future)
  │     └── restaurantPricing.strategy.js
  └── registry: serviceType → strategy
```

### 10.2 규칙 테이블 통합 (Admin UI)

| UI 모듈 | 테이블 |
|---------|--------|
| Vehicle Capacity | `vehicle_capacity_rules` |
| Base Price | `vehicle_price_rules` |
| Surcharges | `charge_policies` |
| Driver Auto-Assign | `driver_assignment_weights` |
| Notifications | `notification_rules` |

### 10.3 Point / Coupon / Membership (Phase 2)

- Pricing Step 5–6 활성화
- `point_transactions` — COMPLETED 후 적립
- `membership_tiers` — Pricing Step 1 base % discount

### 10.4 Multi-service Booking (장기)

- 하나의 `bookings`에 여러 `service_types` (패키지) → `booking_line_items`  
- 현재는 1 booking = 1 serviceType 유지, 패키지는 상위 `orders` (향후)

### 10.5 Outbox Pattern

```
booking.created → INSERT outbox_events → worker → notification/email
```
DB와 메시지 발송 **정확히 1회** 보장.

### 10.6 SQL 생성 시 추가 테이블 권장

| 테이블 | Engine |
|--------|--------|
| `vehicle_capacity_rules` | Vehicle Recommendation |
| `charge_policies` | Pricing |
| `guest_access_tokens` | Guest (booking_id, hash, expires_at) |
| `notification_rules` | Notification |
| `driver_assignment_weights` | Driver Auto (Phase 2) |
| `outbox_events` | Notification reliability |

기존 v1.1 `booking_charge_items`, `vehicle_price_rules`와 함께 schema에 반영.

---

## 다음 단계

1. **Database SQL** — 본 문서 + DATABASE v1.1 + 신규 rules 테이블 반영  
2. **Repository + Engine Service** 구현 (본 파이프라인 순서)  
3. **OpenAPI ↔ Validator** 1:1 연결  
4. **Admin UI** — rules CRUD

---

*Document version: 1.0 | Pre-SQL Business Engine | 2026-06-26*
