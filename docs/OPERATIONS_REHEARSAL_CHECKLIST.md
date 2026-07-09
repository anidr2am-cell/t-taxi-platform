# T-Ride Operations Rehearsal Checklist

실운영 전 고객, 관리자, 기사 흐름을 반복 점검하기 위한 수동 운영 리허설 기준이다.
신규 배포 후 회귀 확인과 장애 구간 식별에도 동일하게 사용한다.

## Rehearsal Record

| Item | Value |
|------|-------|
| Date/time (Asia/Bangkok) | |
| Environment / release | Staging / |
| Operator | |
| Developer | |
| Frontend | `http://103.60.127.213:3101/` |
| Backend | `http://103.60.127.213:3100/` |
| Test admin | |
| Test driver | |
| Test booking number | |
| Support receipt number | |
| Overall result | PASS / FAIL |
| Evidence / issue link | |

비밀번호, 토큰, 해시, `.env` 값, 서버 내부 파일 경로 또는 고객 민감정보를
문서, 스크린샷, 이슈에 기록하지 않는다.

## Safety Guardrails

리허설 범위는 `/opt/t-ride`와 `tride-*`로 제한한다.

- `/opt/ktaxi`에 접근하거나 수정하지 않는다.
- `ktaxi-*`를 중지, 재시작, 삭제 또는 재빌드하지 않는다.
- `ktaxi-nginx`를 재시작하지 않는다.
- 호스트 80/443 또는 legacy Compose 파일을 변경하지 않는다.
- `infra_*`, `ktaxi*`, DB volume을 삭제하지 않는다.
- `docker compose down`, `docker compose down -v`, clean migration을 실행하지 않는다.
- `.env`, secret, password, hash, JWT, guest token을 출력하지 않는다.

## 1. 사전 서버 상태 확인

읽기 전용 점검:

```bash
cd /opt/t-ride/deploy/docker

docker ps --format "table {{.Names}}\t{{.Ports}}\t{{.Status}}"

curl -i http://127.0.0.1:3100/api/v1/health
curl -I http://127.0.0.1:3101/
```

- [ ] `tride-backend`가 `Up`이고 healthy이다.
- [ ] `tride-frontend`가 `Up`이고 healthy이다.
- [ ] `tride-db`가 `Up`이고 healthy이다.
- [ ] 기존 `ktaxi-*`가 그대로 `Up`이고 변경되지 않았다.
- [ ] Backend health가 HTTP `200`이다.
- [ ] Frontend가 HTTP `200`이다.
- [ ] 공개 frontend URL이 열린다.
- [ ] 브라우저 Console에 시작을 막는 오류가 없다.

```text
Result:
Evidence:
Notes:
```

## 2. 고객 예약 흐름

- [ ] 고객 홈에 접속한다.
- [ ] 공항 픽업 예약을 시작한다.
- [ ] BKK -> Pattaya 요금이 표시된다.
- [ ] BKK -> Pattaya 요금이 승인된 요금표 이미지와 일치한다.
- [ ] DMK -> Pattaya 요금이 표시된다.
- [ ] DMK -> Pattaya 요금이 승인된 요금표 이미지와 일치한다.
- [ ] 이용 가능한 차량을 선택할 수 있다.
- [ ] 요금표에 없는 조합은 임의 요금 대신 `문의`로 표시된다.
- [ ] 승객, 수하물, 픽업 시간, 고객 정보를 입력한다.
- [ ] 예약 생성에 성공한다.
- [ ] 예약번호가 표시된다.
- [ ] 예약조회 페이지에서 예약번호와 전화번호로 조회한다.
- [ ] 조회 내용이 생성한 예약과 일치한다.

```text
Booking number:
Route / vehicle:
Displayed fare:
Expected fare:
Result:
Evidence:
```

## 3. 고객센터 문의 흐름

- [ ] 고객센터 페이지로 이동한다.
- [ ] 문의하기 팝업을 연다.
- [ ] 이름/닉네임 입력란이 있다.
- [ ] 휴대폰 번호 입력란이 있다.
- [ ] 카카오톡 ID 입력란이 있다.
- [ ] LINE ID 입력란이 있다.
- [ ] 이메일 입력란이 없다.
- [ ] 식별 가능한 테스트 메시지를 입력한다.
- [ ] 민감정보가 없는 테스트 이미지를 첨부한다.
- [ ] 문의 전송에 성공한다.
- [ ] 접수번호가 표시된다.
- [ ] 고객 채팅창에 문의 내용과 첨부가 표시된다.

```text
Receipt number:
Attachment filename/type:
Result:
Evidence:
```

## 4. 관리자 고객센터 흐름

- [ ] 활성 ADMIN 또는 SUPER_ADMIN 계정으로 로그인한다.
- [ ] 고객센터 문의 메뉴에 접근한다.
- [ ] 방금 접수한 문의가 목록에 표시된다.
- [ ] 문의 상세로 이동한다.
- [ ] 고객 휴대폰, 카카오톡 ID, LINE ID가 입력된 범위에서 표시된다.
- [ ] 첨부파일 목록이 표시된다.
- [ ] 이미지 미리보기가 정상이다.
- [ ] 다운로드가 정상이다.
- [ ] UI, URL, 응답에 서버 내부 파일 경로가 노출되지 않는다.
- [ ] 식별 가능한 테스트 답변을 작성하고 전송한다.
- [ ] 상태가 `IN_PROGRESS`로 반영된다.
- [ ] 고객 채팅창에서 관리자 답변을 확인한다.

```text
Admin email (no password):
Reply marker:
Result:
Evidence:
```

## 5. 관리자 예약/배차 흐름

- [ ] 관리자 예약 목록에 접근한다.
- [ ] 신규 예약이 표시된다.
- [ ] 예약 상세가 열린다.
- [ ] 고객 정보가 정확하다.
- [ ] 출발지와 목적지가 정확하다.
- [ ] 픽업 시간이 Thailand time 기준으로 정확하다.
- [ ] 차량 종류가 정확하다.
- [ ] 테스트 기사를 배정할 수 있다.
- [ ] 배정 후 기사와 상태가 반영된다.
- [ ] 새로고침 후에도 배정 결과가 유지된다.

```text
Booking number:
Assigned driver:
Result:
Evidence:
```

## 6. 드라이버 흐름

- [ ] 활성 테스트 기사 계정으로 로그인한다.
- [ ] 기사 화면의 제목과 라벨이 한국어+태국어로 병기된다.
- [ ] 오늘 배정된 예약이 표시된다.
- [ ] 예약 상세에 진입한다.
- [ ] 고객 연락처가 표시된다.
- [ ] 픽업 장소가 표시된다.
- [ ] 목적지가 표시된다.
- [ ] 픽업 시간이 표시된다.
- [ ] `운행 시작 / เริ่มเดินทาง` 버튼이 표시되고 상태 변경이 정상이다.
- [ ] `기사 도착 / ถึงจุดรับแล้ว` 버튼이 표시되고 상태 변경이 정상이다.
- [ ] `운행 완료 / จบงาน` 버튼이 표시되고 상태 변경이 정상이다.
- [ ] 완료 후 목록과 상세의 상태가 일치한다.

```text
Driver identifier (no password):
Booking number:
Status sequence:
Result:
Evidence:
```

## 7. 정산 화면

- [ ] 기사 정산 화면에 접근한다.
- [ ] 한국어+태국어가 병기된다.
- [ ] 적용 가능한 미정산/제출/정산 상태가 표시된다.
- [ ] 금액과 통화가 정확히 표시된다.
- [ ] 처리되지 않은 오류 없이 로딩된다.
- [ ] 영수증 업로드를 확인한다면 민감정보 없는 테스트 파일만 사용한다.

```text
Booking number:
Settlement status:
Amount:
Result:
Evidence:
```

## 8. 장애 발생 시 1차 확인

모든 명령은 `/opt/t-ride/deploy/docker`에서 실행한다. 컨테이너 wildcard를 사용하지
않고 환경변수를 출력하지 않는다.

### Frontend 접속 불가

```bash
docker ps --filter "name=tride-frontend" --format "table {{.Names}}\t{{.Ports}}\t{{.Status}}"
curl -I http://127.0.0.1:3101/
docker compose -f docker-compose.staging.yml logs --tail=100 tride-frontend
```

브라우저 Network/Console, frontend health, `3101` 포트를 확인한다.
nginx, 80/443, `ktaxi-*`는 변경하지 않는다.

### Backend health 실패

```bash
docker ps --filter "name=tride-backend" --format "table {{.Names}}\t{{.Ports}}\t{{.Status}}"
curl -i http://127.0.0.1:3100/api/v1/health
docker compose -f docker-compose.staging.yml logs --tail=150 tride-backend
```

HTTP 상태, 안전한 error code, 발생 시간을 기록한다. 로그 공유 전 token/secret을 가린다.

### DB disconnected

```bash
docker ps --filter "name=tride-db" --format "table {{.Names}}\t{{.Ports}}\t{{.Status}}"
docker inspect --format "{{.Name}} {{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{end}}" tride-db
docker compose -f docker-compose.staging.yml logs --tail=100 tride-db
docker compose -f docker-compose.staging.yml logs --tail=100 tride-backend
```

DB credential을 출력하거나 DB volume을 삭제하거나 clean migration을 실행하지 않는다.

### 고객센터 문의 저장 실패

```bash
curl -i http://127.0.0.1:3100/api/v1/health
docker compose -f docker-compose.staging.yml logs --since=10m tride-backend
```

브라우저 요청 시간, HTTP 상태, 안전한 error code를 기록한다. Authorization header,
guest token, 문의 민감정보, 첨부 원본은 복사하지 않는다.

### 첨부 이미지 미리보기 실패

문의 상세의 Network 요청, HTTP 상태, `Content-Type`, Console을 확인하고 최근 backend
로그를 조회한다.

```bash
docker compose -f docker-compose.staging.yml logs --since=10m tride-backend
```

저장 경로, credential, token, 고객 파일을 이슈에 노출하지 않는다.

### 기사 상태 변경 실패

화면에서 현재 상태와 허용 action을 확인하고 한 번 새로고침한 뒤 정상적인 다음
transition만 재시도한다.

```bash
curl -i http://127.0.0.1:3100/api/v1/health
docker compose -f docker-compose.staging.yml logs --since=10m tride-backend
```

예약번호, 이전 상태, 요청 action, 안전한 error code, 시간을 기록한다. DB 상태를 직접
수정하거나 validator를 우회하지 않는다.

### 관리자 로그인 실패

`docs/STAGING_ACCOUNT_RESET.md`의 승인된 절차로 이메일, role, active 상태를 확인한다.

```bash
curl -i http://127.0.0.1:3100/api/v1/health
docker compose -f docker-compose.staging.yml logs --since=10m tride-backend
```

비밀번호, hash, 로그인 응답 body, JWT 또는 `.env`를 출력하지 않는다.

### 금지 복구 명령

다음을 1차 복구 수단으로 실행하지 않는다.

```bash
cd /opt/ktaxi
docker compose down
docker compose down -v
docker volume rm tride_mysql_data
docker restart ktaxi-nginx
docker stop ktaxi-backend
docker stop ktaxi-frontend
```

동등한 wildcard 또는 volume 삭제 명령도 금지한다.

## 9. 배포 후 확인 순서

### Frontend-only

1. `tride-frontend` health와 `3101` HTTP `200`을 확인한다.
2. 고객 홈을 확인한다.
3. 고객센터 페이지와 문의 팝업을 확인한다.
4. 기사 로그인, 예약, 프로필 화면을 확인한다.
5. 한국어+태국어 병기와 360px 레이아웃을 확인한다.

Backend rebuild와 DB migration은 불필요하다.

### Backend

1. Backend health HTTP `200`을 확인한다.
2. 고객센터 문의 생성과 조회를 확인한다.
3. 정상 예약 UI를 통해 pricing을 확인한다.
4. 응답 token을 기록하지 않고 관리자 로그인을 확인한다.
5. 배포 범위의 읽기 동작과 안전한 상태 변경 동작을 각각 확인한다.

### DB migration 포함

1. 실행 전에 migration 범위, backup, rollback 계획을 검토한다.
2. 승인된 `migrate.sh` 절차를 실행하고 비밀정보 없는 결과를 보관한다.
3. destructive reset 없이 migration이 완료되었는지 확인한다.
4. Backend와 DB health를 확인한다.
5. 변경된 table을 읽거나 쓰는 모든 관련 기능을 수동 확인한다.
6. Clean migration 또는 DB volume 삭제는 절대 사용하지 않는다.

## 10. PASS 기준

- [ ] 고객 예약 생성 가능
- [ ] 고객 예약 조회 가능
- [ ] 승인된 요금이 기준 이미지와 일치
- [ ] 없는 요금은 `문의` 처리
- [ ] 고객센터 문의와 이미지 첨부 가능
- [ ] 관리자 문의 확인과 답변 가능
- [ ] 고객 답변 확인 가능
- [ ] 관리자 기사 배정 가능
- [ ] 기사 상태 변경 가능
- [ ] 드라이버 화면 한국어+태국어 병기
- [ ] 정산 화면 정상 로딩
- [ ] Secret, token, hash, 내부 첨부 경로 미노출
- [ ] KTaxi 컨테이너와 기능에 영향 없음

## 11. FAIL / Stop-Go 기준

다음 중 하나라도 해당하면 실운영 전 배포를 중단한다.

- [ ] `ktaxi-*` 컨테이너 또는 KTaxi 기능 영향
- [ ] Backend health 실패
- [ ] DB disconnected/unhealthy
- [ ] 예약 생성 실패
- [ ] 요금 계산 실패 또는 승인 요금과 불일치
- [ ] 고객센터 문의 저장 실패
- [ ] 관리자 문의 확인/답변 불가
- [ ] 기사 상태 변경 실패
- [ ] 첨부파일 저장 경로 또는 내부 식별자 노출
- [ ] 비밀번호, hash, JWT, guest token, API key, `.env` 값 노출
- [ ] 필수 점검 증거가 없거나 blocking issue 미해결

실패 시 배포를 멈추고 비밀정보 없는 증거, 최초 실패 단계, 담당자를 기록한다.
수정 후 영향받은 흐름 전체를 다시 확인한다.

## Final Sign-Off

| Role | Name | Result | Date/time | Notes |
|------|------|--------|-----------|-------|
| Operator | | PASS / FAIL | | |
| Developer | | PASS / FAIL | | |
| Release approver | | GO / NO-GO | | |

