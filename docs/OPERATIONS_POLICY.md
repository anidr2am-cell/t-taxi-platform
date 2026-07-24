# 운영 정책 결정 기록

마지막 갱신: 2026-07-25

## 1. 기사 반복 반납(배정 취소) 제재 기준
**결정:** 느슨하게 - 누적만 기록, 당장 제재 없음
**근거:** booking_driver_assignments + booking_activity_logs에 이미
기사별 반납 이력이 전부 쌓이고 있음 (assignment_reason =
'DRIVER_RELEASED_ASSIGNMENT' 기준 집계 가능). 추가 개발 없이 SQL로
언제든 조회 가능.
**조회 쿼리 예시:**
```sql
SELECT driver_id, COUNT(*) AS release_count
  FROM booking_driver_assignments
 WHERE assignment_reason = 'DRIVER_RELEASED_ASSIGNMENT'
   AND is_active = 0 AND deleted_at IS NULL
 GROUP BY driver_id;
```
**재검토 시점:** 자동 벌점·정지 기능 개발 시 이 기준부터 다시 논의

## 2. 긴급 반납(2시간 이내 CRITICAL) 증빙 자료
**결정:** 불필요 - 사유 텍스트(reasonCode/reasonDetail)만으로 충분
**현재 구현:** driverAssignmentRelease.policy.js, 사유 코드 기반 검증만 존재
**재검토 시점:** 악용 사례 발생 시

## 3. 고객 취소 수수료·환불 정책
**결정:** 현재처럼 전액 환불, 수수료 없음
**현재 구현:** 2시간 경계 규칙만 적용 (그 외 수수료 로직 없음)
**재검토 시점:** 노쇼/임박 취소가 운영상 문제가 될 경우

## 4. 픽업 2시간 이내 관리자 강제 취소
**결정:** 관리자가 언제든 제한 없이 강제 취소 가능
**현재 구현:** PATCH /admin/bookings/:bookingNumber/status - 별도 시간 제약 없음
**재검토 시점:** 없음 (현행 유지)

## 5. 자동 벌점·정지 기능
**결정:** 나중에 개발, 현재 미착수
**현재 상태:** 이력 데이터는 이미 축적 중이라 향후 개발 시 과거 데이터
소급 활용 가능
**향후 개발 시 필요 작업 (참고):**
- GET /admin/drivers/:id/release-history API 신규
- 기사 상세 화면 신규 (현재 기사 상세 화면 자체가 없음)
- 기간별/사유별 집계 로직
- 벌점 임계치, 정지 기간 등 세부 규칙 별도 결정 필요

---
이 문서는 정책이 바뀔 때마다 갱신합니다. 변경 시 "마지막 갱신" 날짜와
해당 항목만 수정하고, 이전 결정 이력이 궁금하면 git log로 확인 가능합니다.
