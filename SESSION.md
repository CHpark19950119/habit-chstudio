# Session Handoff
> 이 파일은 Claude Code 세션 간 작업 연속성을 위한 핸드오프 문서.
> 세션 종료 시 자동 업데이트됨. 다음 세션 시작 시 이 파일부터 읽는다.

## 마지막 세션
- **날짜**: 2026-03-19
- **버전**: v10.14.0
- **커밋**: `b522d4c` feat: 홈데이 헤더 인라인 + 고시 크롤러 복구

## 이번 세션 완료 작업

### 1. 자동 기상 감지 수정 (`3bcd50c`)
- Tuya 센서 극성 반전 수정 (true=open)
- `openedToday` 플래그 — 7시 전 문 열어도 7시 폴링에서 즉시 감지
- FCM notification 페이로드 추가 (Android Doze 우회)
- 앱 `_recoverWakeFromFirestore()` — Firestore 서버 직접 읽기 (캐시 우회)

### 2. IoT 자동화 확장 (`4c19e7e`)
- mmWave presence 폴링 (pollDoorSensor 통합, 매 1분)
- 취침 자동 감지 (peaceful + ≤200cm + 23~07시 + 30분 연속)
- 전등 제어: 외출 OFF, 귀가 ON(18시+, bedTime 가드), 취침 OFF
- `sendTuyaCommand()`, `setLight()`, `checkSleepByPresence()`
- FCM sleep 처리 (fg + bg)
- 홈 presence 카드 (StreamBuilder)
- 설정 수면감지 토글 제거

### 3. 홈데이 리브랜딩 (`27ec870`, `b522d4c`)
- 칩거 → 홈데이 전체 리네임
- 홈 UI 통일 (별도 페이지 제거 → 배경 그라데이션 전환)
- 홈데이 헤더 인라인 (카드→기존 구조 동일, 색만 전환)
- 캘린더 홈데이 표시 (인디고 틴트 + 도트)

### 4. 고시 크롤러 복구 (`b522d4c`)
- pollGosiNotice (매일 08:00) + checkGosiManual
- 사이버국가고시센터 공지사항 크롤링
- **미해결**: gosi.kr이 GCP IP 차단 (ECONNRESET)

## 미커밋 파일
- 없음

## 결정사항
- Tuya 웹훅 전환 불필요 — 1분 폴링으로 충분
- mmWave presence_state 실제 값: none/presence/peaceful (계획서의 movement/stationary와 다름)
- bedTime = 최우선 가드 (기록 후 전등 ON/취침 재감지 전부 잠금)
- 홈 대시보드 전체 리디자인 — 다음 세션 (카드 나열→정보 밀도 높이는 방향)

## 다음 할 일
- [ ] 내일 아침 자동 기상 테스트 (극성 수정 확인)
- [ ] 오늘 밤 자동 취침 테스트 (mmWave 30분)
- [ ] 홈 대시보드 리디자인 (나열식 카드 → 리듬+그루핑)
- [ ] mmWave 추가: 방 비움→전등 OFF, 방 진입→전등 ON
- [ ] 고시 크롤러 대안 (로컬 Python 또는 다른 클라우드)
- [ ] 크리처 알람 식사 리마인더 확장

## 알려진 이슈
- gosi.kr GCP IP 차단 (ECONNRESET)
- Codemagic CI 미검증
- 서명: release 빌드가 debug keystore 사용 중
