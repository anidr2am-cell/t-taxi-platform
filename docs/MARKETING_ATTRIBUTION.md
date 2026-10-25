# 게시물별 예약 출처 (2026-10-26)

외부 홍보 링크의 `utm_source`, `utm_medium`, `utm_campaign`, `utm_content`를 사용한다.
예: Facebook / organic_social / 202611_golf_planning / story_20261101.
동일 사이트 블로그→예약 링크에 별도 UTM을 만들지 않는다.

## 저장과 동의

- 정적 랜딩·블로그가 같은 수집 코드를 사용한다. 언어 변경과 블로그·예약 이동 시
  동의 미선택 상태에서는 허용된 UTM 값만 링크에 이어 붙이고 저장/전송하지 않는다.
- 분석 허용 시 같은 origin의 기존 first/last-touch 저장소에 최대 90일 보관한다.
  거부/철회 시 삭제하며 예약은 그대로 가능하다. 브라우저 저장소 차단도 예약을 막지 않는다.
- 첫 유입은 유지하고 이후 외부 캠페인 유입은 last touch로 기록한다. 내부 링크가
  외부 캠페인을 덮어쓰지 않는다. 관리자·기사·계정·OAuth 경로를 유입으로 수집하지 않는다.
- 예약 앱은 동의한 출처만 기존 예약 API로 보내고, 서버가 허용 필드를 정제해
  bookings.metadata.marketing_attribution.first_touch / last_touch에 기록한다.
  이 변경에는 DB 마이그레이션, 요금·결제·배차 변경이 없다.
- GA4에는 전체 쿼리 대신 정제한 campaign_* 설정과 traffic_* 예약 이벤트 정보를 쓴다.
  예약 이벤트 출처는 전송 시점에 다시 읽어 예약 중 동의한 경우도 반영한다.

## 성과 확인

원본 게시물 ID/공개 URL과 UTM을 대조하고 최초 유입과 마지막 캠페인을 별도로 표시한다.
읽기 전용 집계 예시(기간은 운영 보고 범위로 바꾼다):

```sql
SELECT booking_source, status,
 JSON_UNQUOTE(JSON_EXTRACT(metadata,'$.marketing_attribution.last_touch.source')) AS source,
 JSON_UNQUOTE(JSON_EXTRACT(metadata,'$.marketing_attribution.last_touch.campaign')) AS campaign,
 JSON_UNQUOTE(JSON_EXTRACT(metadata,'$.marketing_attribution.last_touch.content')) AS content,
 COUNT(*) AS bookings
FROM bookings
WHERE deleted_at IS NULL AND created_at >= '2026-10-27 00:00:00'
GROUP BY booking_source, status, source, campaign, content;
```

관리자 수기(ADMIN_MANUAL), 테스트·중복·취소 상태를 구분한다. 출처 없는 예약은 미확인으로
남기며 GA4 booking_completed 횟수를 실제 예약 건수로 대신하지 않는다. Meta 조회/링크 클릭,
GA4 방문, 실제 예약은 각 원본과 동일 기간·시간대로 비교한다.

Instagram 캡션의 주소/이미지 주소는 클릭 가능한 게시물별 링크가 아니다. 공통 프로필 링크,
직접 주소 입력, 다른 기기, 메신저 상담 후 수기 예약, 분석 거부, 링크 표식 제거 등은 특정
게시물로 확정할 수 없다. 이 기능은 과거 출처를 소급 복원하거나 광고 기여의 인과성을
증명하지 않는다. 확인되지 않은 예약을 임의로 배분하지 않는다.

검증: Node 실제 공유 스크립트 실행(동의·언어·블로그·TTL·저장소 차단), Flutter 저장소→예약
payload, 서버 createBooking→repository metadata 검증. 운영 확인은 실제 고객 예약 생성 없이
정적 자산과 예약 화면·서비스 응답을 검사한다.

GA4 설정 근거: https://developers.google.com/analytics/devguides/collection/ga4/reference/config
