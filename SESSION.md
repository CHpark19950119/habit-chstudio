# Session Handoff
> 이 파일은 Claude Code 세션 간 작업 연속성을 위한 핸드오프 문서.
> 세션 종료 시 자동 업데이트됨. 다음 세션 시작 시 이 파일부터 읽는다.

## 마지막 세션
- **날짜**: 2026-03-21
- **버전**: v10.14.1
- **커밋**: `34bd30c` — 자동취침 오판 방지 + wake 기반 날짜 귀속 + 캐시 동기화

## 이번 세션 완료 작업

### 1. 자동취침 오판 방지 — 폰 사용 중 취침 감지 차단
- BixbyNotificationListener에서 SCREEN_ON 시 `phone.lastScreenOn` Firestore 기록 (5분 throttle)
- CF `checkSleepByPresence`에서 lastScreenOn 30분 이내면 취침 스킵
- 침대에서 폰 사용 중 peaceful로 잡혀도 취침 안 찍힘

### 2. wake 기반 bedTime 날짜 귀속 알고리즘
- 기존: 4AM 경계 + 4~7시 예외 → 경계 애매, 롤오버 후 중복 취침 버그
- 변경: wake 있고 bedTime 없는 가장 최근 날짜에 bedTime 기록
- CF + 앱(`day_action_part.dart`) 양쪽 동일 알고리즘 적용

### 3. today doc 캐시 동기화
- today doc 스트림 수신 시 로컬 캐시(SharedPrefs) 갱신
- `_parseStudyData`에서 timeRecords 파싱 제거 → today doc 단일 소스
- study doc 스트림에서 `_prevBedTime` 갱신 (수면시간 실시간 반영)

### 4. CF 데이터 조회/수정 엔드포인트
- `checkDoorManual?q=date&date=2026-03-20` → study doc timeRecords 조회
- `checkDoorManual?q=date&doc=today` → today doc 전체 조회
- `checkDoorManual?q=set&date=...&field=...&value=...` → timeRecords 수정/삭제

### 5. Codemagic 자동 트리거 비활성화
- `codemagic.yaml` events: [] → push 시 빌드 안 돌아감, 메일 안 옴

### 6. 3/20 bedTime 수정
- 02:19(mmWave 오판) → 05:30(실제 취침) 수정
- 3/21 bedTime 05:38(버그 중복) 삭제

## 미커밋 파일
- `telegram_claude.js` (untracked, 로컬 전용)

## 결정사항
- bedTime 날짜 귀속: wake 기반 (시간 경계 X)
- 취침 판정 조건: mmWave peaceful + 침대 zone + 화면 30분 OFF + stationarySince 30분
- timeRecords는 today doc에서만 읽음 (study doc 충돌 방지)
- Codemagic은 트리거 꺼둠 (로컬 빌드 사용)

## 다음 할 일
- [ ] 오늘 밤 자동취침 정상 동작 확인 (화면 OFF 30분 + mmWave)
- [ ] AI 비서 전반적 앱 관리 기능 확장
- [ ] 홈 대시보드 리디자인
- [ ] 고시 크롤러 대안 (로컬 Python)
- [ ] 헤드위그 mmWave 연동

## 알려진 이슈
- gosi.kr GCP IP 차단
- 무선충전 스탠드 자동화 불가
- 서명: release 빌드가 debug keystore 사용 중
