# Driver App Development Backlog

## 1. 다국어 지원 (태국어 우선)

### 배경

기사 앱 이용자는 전원 태국인이므로 태국어가 기본 언어여야 한다.
개발 중에는 태국어와 한국어를 병기하고, 개발 flag로 병기 표시를 on/off 할 수 있게 두는 방향이 적합하다.
출시 전에는 한국어를 제거하고 태국어만 남기는 방식으로 정리한다.

### 처리 방향

처음부터 Flutter 표준 i18n 구조인 `flutter_localizations`와 `.arb` 파일 기반으로 설계한다.
기능 개발이 끝난 뒤 화면별 하드코딩 문구를 한 번에 수집하고, 태국어 기본 문구와 개발용 한국어 병기 문구를 분리한다.

### 상태

미착수. 모든 기능 개발 완료 후 마지막에 전체 화면 일괄 작업 예정.

## 2. 정산(settlement) 프로세스

### 배경

운행 종료(`end-trip`) 후 `SETTLEMENT_PENDING` 상태 이후의 정산 목록 조회, 정산 차단 상태 확인 등이 아직 구현되어 있지 않다.
이 항목은 4-C 단계에서 의도적으로 범위 제외됐던 항목이다.

### 처리 방향

backend 계약을 먼저 조사해 기사 앱에서 필요한 정산 상태, 정산 목록, 정산 상세, 정산 차단 조건을 확정한다.
확정 후 계정 또는 별도 정산 탭/화면으로 노출할지 UI 위치를 결정한다.

### 상태

완료. 정산 목록/상세/송금증 업로드, 4탭 확장, 미해결 정산 차단 배너 구현 완료.

## 3. 긴급콜 반납 시 고객 안내

### 배경

기사가 긴급콜(`urgent-call`)을 확정한 뒤 `release`로 배정을 반납하면, 현재 고객에게 변경 사실을 알릴 방법이 없다.
일반 배정 release의 재배정 로직(`OPEN` 복귀, `reassignmentPriority`)이 긴급콜 확정 후 release에도 동일하게 적용되는지 확인이 필요하다.

### 처리 방향

backend와 고객단 정책을 먼저 논의한다.
고객 안내가 필요한 경우 push 알림, 고객 앱 상태 갱신, 예약 상세 안내 문구를 함께 설계한다.
FCM(4-B) 작업과 함께 묶어서 처리하는 것이 효율적일 수 있다.

### 상태

보류. 아이디어 단계이며 backend/고객단 정책 논의 필요.

## 4. FCM 백그라운드 푸시 (4-B)

### 배경

새콜/긴급콜 알림은 앱이 foreground일 때 Socket.IO 기반으로 갱신되지만, 백그라운드 푸시 파이프라인은 아직 연결되어 있지 않다.

### 처리 방향

backend에서 새콜/긴급콜 이벤트를 FCM으로 발송하는 파이프라인을 확장하고, driver_app에서는 토큰 등록, 권한 요청, foreground/background 처리, 알림 탭 이동 흐름을 구현한다.

### 상태

미착수. backend 확장 필요, 별도 논의 예정.

## 5. 지도 렌더링 (3-B)

### 배경

현재는 앱 내부 지도 렌더링 없이 외부 지도 앱 링크로만 대체 중이다.

### 처리 방향

우선 현재 외부 지도 앱 링크 방식으로 운행 흐름을 안정화한다.
이후 우선순위가 올라가면 Google Maps 또는 다른 지도 SDK 도입 여부를 검토한다.

### 상태

미착수. 우선순위 낮음.

## 6. iOS

### 배경

iOS 실 빌드와 서명은 Mac 구매 후 진행 예정이다.
현재 로컬에는 iOS 플랫폼 파일이 존재하며 커밋 완료된 상태다.

### 처리 방향

Mac 환경에서 CocoaPods, signing, bundle id, provisioning profile을 구성한 뒤 실제 빌드와 기기 테스트를 진행한다.

### 상태

로컬 iOS 플랫폼 파일 존재. 실 빌드/서명은 미착수.

## 7. 수완나품 공항 게이트 안내

### 상태

완료. 1~6단계 전부 배포 완료.

### 완료 요약

- backend: `nameSignRequested` 목록/새콜 API 노출 (커밋 `9c26d39`)
- backend: `nameSignText` 컬럼 + 검증 + 저장 + 응답 노출 (커밋 `b81238b`)
- backend: 피켓 사진 업로드/조회 API - 기사용 + 게스트용 (커밋 `f173e83`)
- 고객웹: 피켓 이름 입력 UI (커밋 `c57a2ad`)
- 고객웹: 피켓 사진 표시 화면
- driver_app: 피켓 사진 업로드 화면 (`DRIVER_ARRIVED` 상태 강조 노출)
- driver_app: 목록/상세 화면 게이트 3/7번 안내 및 피켓 관련 UI

## 9. 기술 부채: locationDetails() 로직 중복

`locationDetails()` 로직이 `driverJob.service.js`, `booking.service.js`, `guestBookingLookup.service.js` 세 곳에 복제되어 있음. 향후 장소명 표시 로직 변경 시 세 곳 모두 수정 필요. 리팩터링 우선순위 낮음.

## 10. 관리자 강제 배정취소 (unassign-driver)

### 상태

완료. 배포 완료. 실사용 검증 완료.

### 완료 요약

- backend: admin unassign-driver API (커밋 `ab32215`)
- frontend: 관리자 웹 버튼/dialog (커밋 `a0c2335`)
- driver_app: `ADMIN_RELEASED` vs `DRIVER_RELEASED` 구분 안내 메시지 (커밋 `829fc99`)
- backend: 배포 중 발견된 `openDriverCallSelectSql()`의 `name_sign_requested` SQL 버그 수정 (커밋 `3d5baf8`)

## 11. 예약 시간 기본값 과거값 버그

### 상태

완료. 배포 완료.

### 완료 요약

- frontend: `BookingWizardController.initialize()` 시 SharedPreferences에 저장된 과거 `pickupDate`/`pickupTime`이 더 이상 유효하지 않으면 `defaultPickupDateTime()`(현재+2시간)으로 재설정 (커밋 `dfba80f`)
- `reset()`에서도 기본 pickup 시간 재설정

## 12. 고객웹: 피켓 이름 입력창 나라별 언어 예시 표기

### 배경

'피켓에 표시할 이름' 입력창에 예시 텍스트를 나라별 언어로 보여달라는 요청 (예: 태국어 사용자에게는 태국어 예시).

### 위치

`frontend/lib/features/booking/widgets/step_passengers_luggage.dart`의 `nameSignText` 입력 필드 근처.

### 상태

미착수.

## 13. 전 화면 장소명 강조 표시 확장 (고객웹/기사웹/관리자)

### 배경

출발지/도착지 주소만으로는 기사가 위치를 파악하기 어려움.
driver_app의 새 콜 목록에는 이미 장소명(수완나품공항, 힐튼파타야 등)을 주소 위에 강조 표시하도록 완료함.
backend가 `pickupLocation`/`destinationLocation`을 open calls에도 노출하도록 이미 확장됨 (커밋 `8da62ba`, `984c479` 참고).

### 남은 작업

- a) 고객웹 예약 완료/조회 화면에 동일하게 장소명 강조 표시
- b) 기사 웹 (`frontend/lib/features/driver/`)에도 동일 적용
- c) 관리자 화면 (`admin_dispatch`)의 예약 목록/상세에도 동일 적용

### 참고

backend 데이터는 이미 존재 (`metadata` 기반). 각 화면 UI 표시 작업만 남음.

§13 참고: 국내선 공항 확장은 현재 범위 아님. 현재 앱에 등록된 공항은 BKK/DMK/CNX/HKT/UTP 5개뿐(frontend의 `thailand_registered_airports.dart`, `airport_shortcuts.dart`). 국내선 공항을 나중에 추가하려면: (1) frontend에 LocationOption 추가, (2) 태국어 공식명칭 확보, (3) backend `thailandAirports.constants.js`에 매핑 추가, (4) 관련 DB seed 파일(`15_pricing_architecture.sql` 등, 파일 상단 주석에 명시된 동기화 대상)도 함께 갱신 필요.

### 상태

부분 완료. driver_app만 완료, 나머지 3곳(고객웹/기사웹/관리자) 미착수.
