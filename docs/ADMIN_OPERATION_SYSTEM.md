# TTaxi Platform — Admin Operation System Design (v1.0)

> **단계**: SQL·코드 작성 **전** 운영(Admin) UX·업무 흐름 설계  
> **대상 사용자**: 여행사 운영 직원, CS, 디스패처, 슈퍼관리자  
> **목표**: 하루 **수백 건** 예약을 **단일 플랫폼**에서 실시간 처리  
> **기준**: PRD · Database v1.1 · Business Engine · API Contract · OpenAPI

---

## 0. 운영 조직과 권한 모델

### 0.1 Role 정의

| Role | 설명 | 대표 업무 |
|------|------|-----------|
| **OPERATOR** (향후) | 일반 운영 | 예약 확인, 채팅, 상태 변경 |
| **ADMIN** | 관리자 | 배정, 가격, 기사, 통계 |
| **SUPER_ADMIN** | 시스템 | API Key, 설정, Role 변경, 감사 |

> MVP: OpenAPI `ADMIN` + `SUPER_ADMIN`만 사용. OPERATOR는 Phase 2 RBAC 확장.

### 0.2 권한 매트릭스 (요약)

| 기능 | ADMIN | SUPER_ADMIN |
|------|-------|-------------|
| Dashboard / Booking 조회·수정 | ✓ | ✓ |
| 기사 배정 / 변경 | ✓ | ✓ |
| 관리자 메모 (private) | ✓ | ✓ |
| Live Chat 참여 | ✓ | ✓ |
| Pricing / Vehicle rules CRUD | ✓ | ✓ |
| Statistics (전체) | ✓ | ✓ |
| System Settings / API Keys | ✗ | ✓ |
| User/Driver 계정 생성·삭제 | ✓ | ✓ |
| 감사 로그 / Role 변경 | ✗ | ✓ |

### 0.3 운영 화면 네비게이션 (IA)

```
Admin Shell (NavigationRail / Sidebar)
├── Dashboard          ← 실시간 KPI
├── Bookings           ← 검색·상세·타임라인
├── Dispatch Board     ← Kanban 배정
├── Live Chats         ← 3자 채팅
├── Flight Monitor     ← 픽업 항공편
├── Driver Monitor     ← 기사·지도
├── Pricing            ← 규칙·미리보기
├── Statistics         ← 리포트
├── Settings           ← SUPER_ADMIN
└── (Future) Golf/Tour/Coupon...
```

---

## 1. 일일 운영 업무 흐름 (Operator Workflow)

### 1.1 아침 오픈 (08:00–09:00)

```
1. Dashboard 확인
   → 오늘 예약 N건, 미배정 M건, 연착 항공편 K건
2. Flight Monitor
   → 당일 AIRPORT_PICKUP 항공편 Scheduled/Estimated/Delay
3. Driver Monitor
   → 온라인 기사 수, 가용 VAN/SUV
4. Dispatch Board
   → "미배정" 컬럼 우선 처리 (픽업 시간 임박 순)
```

### 1.2 피크 시간 (09:00–22:00)

```
[병렬 업무 루프]

A. 새 예약 (PENDING)
   → Booking List 필터 PENDING
   → 상세: 인원·수하물·charge items 확인
   → CONFIRMED 전환 (결제 정책에 따라)
   → Dispatch Board에서 기사 드래그 배정

B. 항공 연착
   → Flight Monitor 알림
   → Booking 상세: flight_estimated 갱신 (수동/자동)
   → Activity: FLIGHT_DELAY_UPDATED
   → 기사 FCM + 채팅 자동 메시지 (템플릿)

C. 고객/기사 채팅
   → Live Chat: 미읽음 우선
   → 3자 대화, 파일 확인, 필요 시 메모

D. 현장 이슈
   → 기사 전화 → Admin 상태 변경 (DRIVER_ARRIVED 등)
   → 추가 요금 (TOLL/WAITING) charge item 추가
```

### 1.3 마감 (22:00–24:00)

```
1. 운행중/미완료 건 점검
2. COMPLETED / NO_SHOW / CANCELLED 정리
3. Statistics → 당일 매출 스냅샷
4. 내일 픽업 Preview (Dashboard date filter)
```

### 1.4 CS 에스컬레이션

```
고객 이메일/전화
  → Booking 검색 (번호, 이름, 전화, 이메일)
  → Activity Log + Status Log + Chat 히스토리
  → 필요 시 취소/재배정/환불 메모 (Phase 2 Payment)
```

---

## 2. Admin Dashboard

### 2.1 목적

**한 화면**에서 당일 운영 상태를 30초 내 파악.

### 2.2 UI 구성

| 영역 | 위젯 | 갱신 |
|------|------|------|
| KPI Cards | 오늘 예약, 오늘 매출, 대기, 미배정, 운행중, 완료, 취소, 노쇼 | 30s poll / WebSocket |
| Status Chart | 상태별 pie/bar | 1min |
| Timeline | 시간대별 픽업 예정 (next 4h) | 1min |
| Alerts | 연착 N건, 미배정 임박, 미읽음 채팅 | realtime |
| Quick Actions | 미배정 보기, Live Chat, Flight Monitor | — |

### 2.3 KPI 정의 (DB 집계)

| KPI | SQL 개념 | 필터 |
|-----|----------|------|
| 오늘 예약 | COUNT bookings WHERE `created_at` today | deleted_at NULL |
| 오늘 매출 | SUM total_amount WHERE created today | status != CANCELLED |
| 대기 예약 | status = PENDING | scheduled today or all |
| 미배정 | CONFIRMED AND driver_id IS NULL | scheduled today |
| 운행중 | DRIVER_ASSIGNED, DRIVER_ARRIVED, PICKED_UP | — |
| 완료 | COMPLETED today | completed_at today |
| 취소 | CANCELLED today | cancelled_at today |
| 노쇼 | NO_SHOW today | — |

### 2.4 필요 API

| Method | Endpoint | 설명 |
|--------|----------|------|
| GET | `/admin/dashboard` | KPI + statusBreakdown |
| GET | `/admin/dashboard/timeline` | (확장) 시간대별 픽업 |
| GET | `/admin/dashboard/alerts` | (확장) 연착·미배정·채팅 |

### 2.5 사용 DB

`bookings`, `booking_status_logs`, `booking_driver_assignments`, `chat_rooms`, `chat_messages`, `booking_transfer_details` (flight delay)

### 2.6 권한

`ADMIN`, `SUPER_ADMIN`

### 2.7 실시간 KPI (향후)

WebSocket channel `admin:dashboard` — booking.status_changed 이벤트 시 KPI delta push.

---

## 3. Booking Management

### 3.1 목적

예약 **검색·필터·상세·수정·감사**의 단일 허브.

### 3.2 Booking List

**검색 (단일 search box)**

- `booking_number` (TX…)
- `customer_name`, `customer_phone`, `customer_email`
- `flight_number`
- `origin_address` / `destination_address` (partial)

**필터**

| 필터 | 값 |
|------|-----|
| status | multi-select |
| service_type | AIRPORT_PICKUP … |
| date | scheduled_pickup_at range |
| payment_status | UNPAID, PAID … |
| driver_id | assigned / unassigned |
| airport | BKK, DMK … |
| country | customer_country_code |

**리스트 컬럼**

번호, 상태, 서비스, 픽업일시, 고객명, 전화, 출발→도착, 차량, 금액, 기사, 채팅미읽음, 생성일

**액션**

상세 열기, 빠른 CONFIRM, 빠른 배정, 채팅 열기

### 3.3 Booking Detail (탭 구조)

| 탭 | 내용 |
|----|------|
| Overview | 상태, 경로, 항공, 인원, 수하물, 차량, 금액 요약 |
| Charges | `booking_charge_items` 라인 편집 (추가/삭제) |
| Timeline | status_logs + activity_logs 시각화 |
| Notes | `booking_admin_notes` (private/public) |
| Chat | embedded 또는 Live Chat으로 이동 |
| Assignment | 배정 이력, 현재 기사, 재배정 |

### 3.4 상태 변경

- Dropdown 또는 단계 버튼 (Business Engine state machine)
- `reason` + `memo` 필수 (취소·노쇼)
- API: `PATCH /bookings/{n}/status`

### 3.5 기사 배정 / 변경

- 배정: `POST /admin/bookings/{n}/assign-driver`
- 해제: `POST /admin/bookings/{n}/unassign-driver`
- 변경 = 해제 + 새 배정 (단일 UX)

### 3.6 관리자 메모

- 복수 메모, `is_private` (기사 앱 노출 여부)
- API: `GET/POST /admin/bookings/{n}/notes`

### 3.7 Activity Log / Timeline

| 소스 | 표시 |
|------|------|
| `booking_activity_logs` | BOOKING_CREATED, DRIVER_CHANGED, CHAT_STARTED … |
| `booking_status_logs` | from → to, changed_by, reason |
| System | flight delay auto-update |

### 3.8 필요 API

| Method | Endpoint |
|--------|----------|
| GET | `/admin/bookings` (search, filters, pagination) |
| GET | `/bookings/{n}` |
| PATCH | `/admin/bookings/{n}` |
| PATCH | `/bookings/{n}/status` |
| POST | `/admin/bookings/{n}/assign-driver` |
| POST | `/admin/bookings/{n}/unassign-driver` |
| GET/POST | `/admin/bookings/{n}/notes` |
| GET | `/bookings/{n}/charges`, POST add charge |
| GET | `/bookings/{n}/activity-logs` |
| GET | `/bookings/{n}/status-logs` |

### 3.9 사용 DB

`bookings`, `booking_passengers`, `booking_luggage`, `booking_transfer_details`, `booking_charge_items`, `booking_status_logs`, `booking_activity_logs`, `booking_admin_notes`, `booking_driver_assignments`, `drivers`, `users`, `chat_rooms`, `service_types`, `vehicle_types`, `airports`, `golf_courses`

### 3.10 권한

조회·수정·배정·메모: `ADMIN`  
charge item 삭제·SUPER 상태 재오픈: `SUPER_ADMIN` (정책)

---

## 4. Driver Dispatch Board (Kanban)

### 4.1 목적

**시각적 디스패처** — 미배정 건을 기사에게 드래그앤드롭 배정.

### 4.2 Kanban 컬럼

| 컬럼 | booking.status / assignment | 카드 내용 |
|------|----------------------------|-----------|
| **미배정** | CONFIRMED, driver_id NULL | 픽업시간, 공항/경로, 인원, 차량, flight |
| **배정 완료** | DRIVER_ASSIGNED, assignment ACCEPTED or ASSIGNED | + 기사명, 차량 |
| **운행중** | DRIVER_ARRIVED, PICKED_UP | + 실시간 상태 |
| **운행 완료** | COMPLETED (당일) | 완료 시각, 금액 |

**옵션 컬럼 (접기)**

- PENDING (확정 전)
- CANCELLED / NO_SHOW (당일)

### 4.3 카드 정렬

- 미배정: `scheduled_pickup_at` ASC (임박 우선)
- 운행중: status progression

### 4.4 드래그앤드롭 동작

```
Drag: Booking card (미배정)
Drop: Driver lane OR "배정 완료" column with driver picker

→ POST assign-driver { driverId, assignmentReason: "dispatch_board" }

Drag: Booking → 다른 Driver lane
→ unassign + assign (재배정 확인 모달)

Drag between status columns (운영자 수동)
→ PATCH status (state machine 검증)
```

**제한**: state machine 위반 드롭 → 스냅백 + toast error

### 4.5 Driver Lanes (보조 뷰)

가로: 기사별 swimlane, 세로: 당일 배정 카드  
→ 한 기사 과배정 시각화

### 4.6 필요 API

| Method | Endpoint |
|--------|----------|
| GET | `/admin/dispatch/board` (확장) — columns + cards |
| GET | `/admin/bookings?status=...&date=today` |
| GET | `/admin/drivers?is_online=true` |
| POST | assign / unassign |
| PATCH | status |

### 4.7 사용 DB

`bookings`, `booking_driver_assignments`, `drivers`, `driver_vehicles`, `booking_transfer_details`, `booking_passengers`, `vehicle_types`

### 4.8 권한

`ADMIN` — 배정·상태 변경

### 4.9 실시간

Socket `admin:dispatch` — status_changed, driver.assigned → 카드 이동

---

## 5. Live Chat Dashboard

### 5.1 목적

고객·기사·관리자 **3자 채팅** 통합 모니터링. CS 응대 시간 단축.

### 5.2 UI 레이아웃

```
┌─────────────┬──────────────────────────┬─────────────┐
│ Room List   │ Message Thread           │ Context     │
│ (필터/검색) │ (3자 말풍선, reply, 파일)│ Booking摘要 │
│ 미읽음 배지 │ 입력 + 파일 업로드       │ 기사 정보   │
└─────────────┴──────────────────────────┴─────────────┘
```

### 5.3 Room List

| 항목 | 설명 |
|------|------|
| 정렬 | 최근 메시지, 미읽음 우선 |
| 필터 | 활성 예약만, service_type, status |
| 검색 | booking_number, customer_name, message content |
| 배지 | unread_count (admin participant) |

### 5.4 Message Thread

- `sender_role`: CUSTOMER / DRIVER / ADMIN (색상 구분)
- `message_status`: SENT / DELIVERED / READ
- `reply_message_id` — 답글 UI
- 파일: image preview, `files` table link
- Admin 발신: `sender_role=ADMIN`, display_name from user

### 5.5 REST + WebSocket

| 동작 | 채널 |
|------|------|
| 히스토리 | GET `/chat/rooms/{code}/messages` |
| 발신 | Socket `send_message` (primary) or REST POST |
| 읽음 | POST `/chat/rooms/{code}/read` |
| 파일 | POST `/chat/rooms/{code}/files` |
| 실시간 | Socket `new_message`, `messages_read` |

### 5.6 Admin 전용

- **모든 room 열람** (예약 status 무관, 감사 목적)
- **Monitor mode**: 발신 없이 읽기만 (OPERATOR role 향후)
- **Join**: room에 ADMIN participant 자동 생성

### 5.7 필요 API

| Method | Endpoint |
|--------|----------|
| GET | `/admin/chats` |
| GET | `/chat/rooms/{code}` |
| GET | `/chat/rooms/{code}/messages` |
| POST | messages, read, files |
| GET | `/bookings/{n}` (context panel) |

### 5.8 사용 DB

`chat_rooms`, `chat_participants`, `chat_messages`, `chat_message_reads`, `files`, `bookings`, `users`

### 5.9 권한

`ADMIN` — 전 room read/write  
`SUPER_ADMIN` — + 삭제/감사 export (향후)

---

## 6. Flight Monitor

### 6.1 목적

**AIRPORT_PICKUP** 당일·내일 항공편 실시간 모니터링 → 연착 시 기사·고객 자동 알림.

### 6.2 UI

| 컬럼 | 데이터 |
|------|--------|
| Booking # | link |
| Flight | KE651 |
| Airport | BKK |
| Scheduled | flight_scheduled_arrival_at |
| Estimated | flight_estimated_arrival_at |
| Delay | delay_minutes, delay_status |
| Pickup | scheduled_pickup_at |
| Driver | assigned or — |
| Actions | Refresh flight, Notify driver |

**행 색상**: 연착 >15min yellow, >60min red, cancelled grey

### 6.3 데이터 소스

| 레이어 | 설명 |
|--------|------|
| DB | `booking_transfer_details` 스냅샷 |
| AviationStack | GET `/flights?flightNumber&date` (백엔드 프록시) |
| Job | `flightSync.job` — 5~10분 polling 당일 픽업 |

### 6.4 연착 시 자동 액션 (Business Engine)

```
IF estimated - scheduled > threshold:
  UPDATE booking_transfer_details
  activity_log: FLIGHT_DELAY_UPDATED
  notification: customer, driver, admin alert
  optional: recalc pickup time suggestion
```

### 6.5 필요 API

| Method | Endpoint |
|--------|----------|
| GET | `/admin/flights/monitor` (확장) — today pickups + flight fields |
| GET | `/flights` | AviationStack proxy |
| POST | `/admin/bookings/{n}/refresh-flight` (확장) |
| POST | `/admin/bookings/{n}/notify-driver-delay` (확장) |

### 6.6 사용 DB

`bookings`, `booking_transfer_details`, `airports`, `booking_activity_logs`, `notifications`

### 6.7 권한

`ADMIN`

### 6.8 자동 새로고침

- UI: 60s client poll 또는 WebSocket `flight.updated`
- Server: cron job + manual refresh button

---

## 7. Driver Monitor

### 7.1 목적

기사 **가용성·위치·배정 부담**을 한 화면에서 파악 → Dispatch Board 보조.

### 7.2 UI

**Map View** + **List View** (toggle)

| List 컬럼 | 소스 |
|-------------|------|
| 이름/전화 | drivers |
| 상태 | AVAILABLE / ON_TRIP / OFFLINE |
| 온라인 | is_online, last_seen_at |
| 차량/번호판 | driver_vehicles |
| 위치 | current_lat/lng, location_updated_at |
| 당일 배정 | COUNT assignments today |
| 평점 | rating_avg (향후) |
| 진행 예약 | active booking_number |

**Map**: 온라인 기사 pin, 클릭 → 상세 + 배정 액션

### 7.3 필요 API

| Method | Endpoint |
|--------|----------|
| GET | `/admin/drivers` |
| GET | `/admin/drivers/monitor` (확장) — location + stats |
| GET | `/admin/drivers/{id}/assignments` (확장) |
| PATCH | `/admin/drivers/{id}` (status override, rare) |

### 7.4 사용 DB

`drivers`, `driver_vehicles`, `users`, `booking_driver_assignments`, `bookings`, `vehicle_types`

### 7.5 권한

`ADMIN` — 조회  
기사 위치 **강제 OFFLINE**: `SUPER_ADMIN` (정책)

### 7.6 실시간

Driver app → `POST /driver/location` every 10–30s  
Admin map WebSocket `driver.location_updated`

---

## 8. Pricing Management

### 8.1 목적

**DB 규칙** CRUD — Business Engine 하드코딩 없이 요금·차량 추천 튜닝.

### 8.2 서브 모듈

#### A. Vehicle Capacity Rules

| UI | CRUD `vehicle_capacity_rules` |
|----|-------------------------------|
| 필드 | vehicle_type, max_passengers, max_20/24/golf/special, priority |
| 테스트 | "시뮬레이터" — 인원/수하물 입력 → 추천 결과 |

#### B. Base Price Rules

| UI | CRUD `vehicle_price_rules` + conditions |
|----|----------------------------------------|
| 필드 | service, vehicle, base_price, priority, valid_from/to |
| 조건 | 요일, 시간대, 공항, 지역, 공휴일, 시즌 |

#### C. Charge Policies (Surcharges)

| UI | CRUD `charge_policies` |
|----|------------------------|
| 타입 | NIGHT, HOLIDAY, AIRPORT, SEASON … |
| modifier | FIXED / PERCENT |

#### D. Fallback Prices

| UI | CRUD `vehicle_prices` |

#### E. 요금 미리보기 (Simulator)

```
입력: service, datetime, airport, region, vehicle assignments, options
→ POST /bookings/pricing/calculate
→ charge items table 표시
```

### 8.3 필요 API

| Method | Endpoint |
|--------|----------|
| GET/POST/PATCH/DELETE | `/admin/vehicle-capacity-rules` (확장) |
| GET/POST/PATCH | `/admin/vehicle-price-rules` |
| GET/POST/PATCH | `/admin/charge-policies` (확장) |
| GET/PATCH | `/admin/vehicle-prices` |
| POST | `/bookings/pricing/calculate` |
| POST | `/bookings/vehicle/recommend` |

### 8.4 사용 DB

`vehicle_types`, `vehicle_capacity_rules`, `vehicle_prices`, `vehicle_price_rules`, `vehicle_price_rule_conditions`, `charge_policies`, `service_types`, `settings` (name_sign_price)

### 8.5 권한

CRUD: `ADMIN`  
`settings` 글로벌 키: `SUPER_ADMIN`

### 8.6 변경 감사

`created_by`, `updated_by` on rules tables — 변경 이력 UI (향후 `audit_logs`)

---

## 9. System Settings

### 9.1 목적

**SUPER_ADMIN** 전용 — API Key, SMTP, 외부 연동, 운영 파라미터.

### 9.2 설정 그룹 (DB `settings`)

| group | keys (예) |
|-------|-----------|
| `google` | maps_api_key (encrypted) |
| `aviation` | aviationstack_api_key |
| `firebase` | project_id, credentials ref |
| `smtp` | host, port, user, password, from |
| `socket` | cors, path |
| `general` | company_name, support_email, support_phone |
| `booking` | guest_token_ttl_days, cancel_policy |
| `dispatch` | auto_assign_mode, delay_threshold_minutes |
| `pricing` | name_sign_price, currency |

### 9.3 UI

- 그룹 탭
- `data_type`: STRING / NUMBER / BOOLEAN / JSON
- SECRET 필드: 마스킹 표시, reveal 버튼
- **테스트 연결**: SMTP test email, Firebase test push, Maps test autocomplete

### 9.4 필요 API

| Method | Endpoint |
|--------|----------|
| GET | `/admin/settings?group=` |
| PUT | `/admin/settings/{group}/{key}` |
| POST | `/admin/settings/test/smtp` (확장) |
| POST | `/admin/settings/test/fcm` (확장) |

### 9.5 사용 DB

`settings`, `users` (updated_by)

### 9.6 권한

**SUPER_ADMIN only** (API Key 노출 방지)

---

## 10. Statistics (Analytics)

### 10.1 목적

경영·운영 리포트 — **읽기 전용**, 대량 집계.

### 10.2 리포트 모듈

| 모듈 | 지표 | 차원 |
|------|------|------|
| **매출** | total_amount, charge_type breakdown | 일/주/월, service_type |
| **예약** | count, conversion PENDING→CONFIRMED | status, service |
| **기사** | completed count, revenue, rating | driver_id |
| **국가** | bookings by customer_country_code | KR, CN, TH … |
| **공항** | pickups by airport_iata | BKK, DMK … |
| **노선** | origin_region → dest_region pairs | top 20 |
| **차량** | vehicle_type distribution | SEDAN/SUV/VAN |
| **리뷰** | avg rating (Phase 2) | driver, golf |

### 10.3 UI

- Date range picker (preset: today, 7d, 30d, custom)
- Export CSV / Excel (Phase 2)
- Chart: line (매출), bar (공항), pie (국가)

### 10.4 필요 API

| Method | Endpoint (확장) |
|--------|-------------------|
| GET | `/admin/statistics/revenue` |
| GET | `/admin/statistics/bookings` |
| GET | `/admin/statistics/drivers` |
| GET | `/admin/statistics/geo` (country, airport, routes) |
| GET | `/admin/statistics/vehicles` |
| GET | `/admin/statistics/reviews` |

### 10.5 사용 DB

`bookings`, `booking_charge_items`, `booking_transfer_details`, `drivers`, `booking_driver_assignments`, `airports`  
**향후**: `booking_daily_stats` materialized (Dashboard/Statistics 공유)

### 10.6 권한

`ADMIN` — 조회  
Export / raw SQL: `SUPER_ADMIN`

### 10.7 성능

- 당일: live query
- Historical: pre-aggregated tables or read replica
- Cache 5min for heavy reports

---

## 11. Future Expansion (Admin IA)

| 모듈 | Admin 화면 | DB (향후) | API prefix |
|------|------------|-----------|------------|
| **Golf** | Golf courses + Golf booking calendar | `golf_courses`, `booking_golf_details` | `/admin/golf-*` |
| **Tour** | Tour packages, inventory | `tour_products`, `booking_tour_details` | `/admin/tours` |
| **Restaurant** | Venue, time slots | `restaurants`, `booking_restaurant_details` | `/admin/restaurants` |
| **Coupon** | Campaign CRUD, usage | `coupons`, `coupon_usages` | `/admin/coupons` |
| **Point** | 적립/사용 규칙 | `point_accounts`, `point_transactions` | `/admin/points` |
| **Membership** | Tier benefits | `membership_tiers`, `user_memberships` | `/admin/memberships` |
| **Wallet** | 잔액, 정산 | `wallets`, `wallet_transactions` | `/admin/wallets` |

**Navigation**: Settings 하위 또는 별도 "Commerce" 섹션 — feature flag `settings.enabled_modules`.

---

## 12. 화면 × API × DB × 권한 (통합表)

| 화면 | 핵심 API | 핵심 DB | Role |
|------|----------|---------|------|
| Dashboard | `/admin/dashboard` | bookings | ADMIN+ |
| Booking List/Detail | `/admin/bookings`, `/bookings/*` | bookings + children | ADMIN+ |
| Dispatch Board | assign, status, drivers | assignments, drivers | ADMIN+ |
| Live Chat | `/admin/chats`, `/chat/*` | chat_*, files | ADMIN+ |
| Flight Monitor | `/admin/flights/monitor`, `/flights` | transfer_details | ADMIN+ |
| Driver Monitor | `/admin/drivers/monitor` | drivers, vehicles | ADMIN+ |
| Pricing | price-rules, capacity-rules, calculate | rules, prices | ADMIN+ |
| Settings | `/admin/settings` | settings | SUPER_ADMIN |
| Statistics | `/admin/statistics/*` | bookings, charges | ADMIN+ |

---

## 13. Admin 클라이언트 기술 방향 (참고 — 구현은 다음 단계)

| 항목 | 권장 |
|------|------|
| UI | Flutter Web (Admin route) 또는 React Admin — PRD는 Flutter Web PWA |
| 상태 | Riverpod + repository |
| 실시간 | Socket.IO admin channels |
| 인증 | JWT ADMIN, refresh, idle logout |
| 동시 편집 | booking version / updated_at conflict detection |

---

## 14. OpenAPI 확장 목록 (SQL 전 정리)

구현 전 Contract에 추가 권장:

- `GET /admin/dispatch/board`
- `GET /admin/flights/monitor`
- `GET /admin/drivers/monitor`
- `GET /admin/statistics/*`
- CRUD `/admin/vehicle-capacity-rules`, `/admin/charge-policies`
- `POST /admin/settings/test/*`

---

## 다음 단계

1. **SQL** — Admin 운영에 필요한 views (`v_dispatch_board`, `v_flight_monitor`) 선택적 포함  
2. **OpenAPI v1.1** — 위 확장 endpoint 추가  
3. **Backend** — `admin/*` routes + read-optimized queries  
4. **Flutter Admin** — Shell + Dashboard + Booking (MVP)

---

*Document version: 1.0 | Admin Operation System | Pre-SQL | 2026-06-26*
