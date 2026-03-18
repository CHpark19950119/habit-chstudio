# CHEONHONG STUDIO — CHANGELOG

## 세션 시작 시 반드시 읽을 것
> 이 섹션만 읽으면 현재 상태 파악 가능. 상세 히스토리는 하단.

### 현재 버전: v10.14.0 (2026-03-19)
- **크리처 알람 시스템 v2:**
  - 분기 이벤트 4개 (칩거확인, 자동기상확인, 장시간공부, 식사리마인더)
  - 크리처 무드 (neutral/worried/curious/proud/sleepy + 오버레이 색상)
  - 메시지 뱅크 (SafetyCheck별 한국어 3개 랜덤)
- **데이터 무결성 가디언:**
  - TimeRecord.validate() — 포맷/순서 검증, 포맷에러 시 쓰기 차단
  - Write-back verify — 3초 후 서버 읽기 비교 + 재시도
  - 듀얼 문서 동기화 (study↔today doc)
  - 캐시 신선도 (30분+ → 서버 리프레시)
- **DataAuditService** — 앱 시작 1일 1회 데이터 검증 + 설정 화면 수동 실행
- **습관 autoTrigger 확장:**
  - 트리거 5종 (wake/sleep/study/outing/meal)
  - 시간 조건부 모드 (triggerTime)
  - 오토뱃지 UI + 시트 트리거 6칩 + 시간 피커
- **진행도 1차/2차 탭 분리** (TabBar + 라운드별 과목 요약)
- **과목 선택 1차/2차 분리** (목표추가 시트 + 포커스존)
- **데일리로그 공부→포커스/휴식 세분화** (FocusCycle 기반)
- **칩거모드 연결 + 수동 토글** (SafetyNet→홈 UI + X 버튼 해제)
- **오더 목표 카드 컴팩트 뷰** (높이 절반)
- **쓰기 보호 강화:**
  - silent catchError 6곳 → 로깅
  - Order _save() 뮤텍스 + 큐잉
  - Rollover 중복 방지
- **버그 수정:** 칩거모드 자정 넘김 (wakeTime 미래 보정)

### 미커밋 파일
- 없음

### 미배포
- 없음 (빌드 + 폰 설치 완료)

### 다음 할 일
- [ ] 경제학 등 신규 과목 로드맵 설정
- [ ] Codemagic CI 검증

### 보류 작업
- 소설 「허락」 제1부 확장 (핸드오프: `assets/roadmap/HANDOFF_소설_허락_제1부.md`)
- 투두→진행도 목표 연결 UI

---

## 히스토리

### 2026-03-19 — v10.14.0 (크리처 알람 v2 + 데이터 무결성 + UI 대폭 개선)
- 크리처 분기 이벤트 4개 + 무드 시스템 + 메시지 뱅크
- 데이터 가디언 (validate, write-back verify, dual sync, cache freshness)
- DataAuditService (앱 시작 1일 1회 + 설정 수동 실행)
- 습관 autoTrigger 확장 (5종 + 시간 조건부 + 오토뱃지)
- 진행도/포커스/목표추가 과목 1차/2차 분리
- 데일리로그 공부→포커스/휴식 세분화
- 칩거모드 연결 + 수동 토글 + 자정 버그 수정
- 오더 목표 컴팩트 뷰
- 쓰기 보호 강화 (로깅, 뮤텍스, rollover 중복 방지)
- 21파일 변경, +1,600줄

### 2026-03-18 — v10.13.1 (데드코드 정리)
- 데드 파일 6개 + 좀비 컨트롤러/페인터 + game/habitat/plan 모듈 삭제 (~5,600줄)
- NfcService→DayService, NfcTagRole→ActionType rename
- Firebase UID 중앙화 (constants.dart)
- Order _update() 레이스컨디션 수정

### 2026-03-18 — v10.11.0
- CF 4AM 경계 적용 + 헤드위그 flat 구조 수정 + 배포
- 앱 재설치 stale movement 방지
- 데일리 로그 세그먼트 직접 편집
- OrderHabit autoTrigger (기상/취침 습관 자동 완료)

### 2026-03-17 — v10.10.0
- DailyGrade 전체 제거 + 순공시간 UI 대체
- 외출/귀가 UI 즉시 반영 아키텍처 (iot → NfcService → home)
- 데일리 로그 스마트 라벨 (NFC 상태 기반)
- Todo ↔ Progress goalId 연결
- 텔레그램 외출/귀가만 유지
- CF onIotWrite Single Writer 패턴

### 2026-03-16 — v10.9.1
- 로드맵 v13 이식, 소설 핸드오프 문서 작성

### 2026-03-15 — v10.9.0
- CF 기상감지 + FCM + 빅스비 외출/귀가 + 공부장소 매칭
- 헤드위그 봇 movement 기반 응답
- 빅스비 NotificationListener 연동

### 2026-03-14 — v10.8.5
- 기상 감지: DayState.idle + 7시 이후 방문 열림

### 2026-03-13 — v10.8.2~v10.8.3
- 헤드위그 텔레그램 위치 봇 + Wake 시간대 설정
- Order v6 커맨드센터, 습관 2단계, 목표 체크리스트

### 2026-03-12 — v10.7.0~v10.8.0
- V9→V11→V13 인생 로드맵, 소설 v4 탑재
- 홈 모션 고급화, 기록탭 차트 모션

### 2026-03-11 — v10.5.0~v10.6.0
- 수면 자동 감지, 문감지 센서, 자동 백업, 일일/주간 리포트
- 버스 도착정보 GBIS API

### 2026-03-10 — v10.2~v10.4.1
- NFC DayState FSM + Geofence
- ORDER v5 리빌드 + HOME 대시보드 v2
- 웹앱 아카이브, 진행도 1차/2차 분리, Todo 강화

### 2026-03-09 이전
- v9.x: 캐시 동기화, 기록탭, 도서관 배치도, Focus Zone
- v6.0: Phase C 아키텍처
- v5.x: Study Creature (Flame)
- v4.x: 3-layer 캐시 + Optimistic UI

---

## 참조

### Firestore 문서 구조 (Phase C)
| 문서 | 용도 | 크기 |
|------|------|------|
| data/today | 홈 전용 (timeRecords, todos, orderData) | ~2KB |
| data/study | 레거시 + 스트림 (전체 데이터) | ~50KB |
| data/iot | IoT 센서 + movement (CF 트리거) | ~1KB |
| data/creature | 캐릭터 | ~1KB |
| data/liveFocus | 실시간 포커스 | ~1KB |
| history/{yyyy-MM} | 월별 아카이브 | ~7KB/월 |
