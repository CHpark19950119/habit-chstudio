# Session Handoff
> 이 파일은 Claude Code 세션 간 작업 연속성을 위한 핸드오프 문서.
> 세션 종료 시 자동 업데이트됨. 다음 세션 시작 시 이 파일부터 읽는다.

## 마지막 세션
- **날짜**: 2026-03-21
- **버전**: v10.14.1
- **커밋**: `9d4e2fa` — today doc 실시간 리스너 + 크리쳐 알림 개선

## 이번 세션 완료 작업

### 1. 수면시간 버그 조사
- Firestore 직접 조회: bedTime="02:47" (텔레그램 "03:57"과 다름)
- 10:02 - 02:47 = 7h15m — 코드 정상, 데이터 차이 문제
- 임시 CF 엔드포인트로 Firestore 데이터 조회 패턴 확립

### 2. SafetyNet(크리쳐 알림) 활성화
- 기본값 `false` → `true` (UI 토글 없어서 한 번도 활성화 안 됐었음)
- 설정 화면에 안전망 ON/OFF 스위치 추가

### 3. Geofence 귀가 감지 복구
- 배터리 최적화(집에서 GPS OFF)가 외출/귀가 감지 완전 차단하는 버그
- `GeofenceService.notifyLeftHome()` 추가 — NFC/빅스비 외출 시 GPS 폴링 시작
- DayService 외출 액션에서 자동 호출

### 4. today doc 실시간 리스너
- `watchTodayData()` Firestore 스트림 추가
- CF가 timeRecords 쓰면 앱 UI 즉시 반영 (캐시 갱신 대기 불필요)
- home_screen에서 study + today 양쪽 리스너 구동

### 5. 크리쳐 알림 UI 수정
- 스프라이트 시트(흰 도트 아티팩트) → 이모지(🐱) + 글로우 호흡 애니메이션
- SafetyNet 체류 알림: `geofence.isHome`이면 "어디에 있냐" 스킵

### 6. 귀가 시간 수동 기록
- 도어센서 `lastChanged` 23:30 KST 기준
- 임시 CF로 returnHome="23:30" Firestore 듀얼 기록

## 미커밋 파일
- `telegram_claude.js` (untracked, 로컬 전용)

## 결정사항
- today doc도 실시간 리스너 사용 (study doc과 동일 패턴)
- SafetyNet 기본 활성화 (설정에서 끌 수 있음)
- 외출 시 GeofenceService.notifyLeftHome() 호출 → GPS 폴링 시작
- 크리쳐 아바타: 스프라이트 시트 → 이모지 + 글로우

## 다음 할 일
- [ ] DayState outing → returned 수동 전환 확인 (앱 재시작)
- [ ] 다음 외출 시 귀가 자동 감지 테스트 (GPS + 전등 + 텔레그램)
- [ ] 크리쳐 알림 실사용 피드백 (어떤 알림이 유용/불필요)
- [ ] 홈 대시보드 리디자인
- [ ] 고시 크롤러 대안 (로컬 Python)
- [ ] AI 비서 tool 확장
- [ ] 헤드위그 mmWave 연동

## 알려진 이슈
- gosi.kr GCP IP 차단
- 무선충전 스탠드 자동화 불가
- Codemagic CI 미검증
- 서명: release 빌드가 debug keystore 사용 중
- 수면시간: bedTime 저장 시점 vs 실제 취침 시점 차이 가능 (30분 stationarySince)
