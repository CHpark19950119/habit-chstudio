# CHEONHONG STUDIO — CHANGELOG

## 세션 시작 시 반드시 읽을 것
> 이 섹션만 읽으면 현재 상태 파악 가능. 상세 히스토리는 하단.

### 현재 버전: v10.11.0 (2026-03-18)
- **이번 세션 변경사항:**
  - CF `kstStudyDate()` 4AM 경계 헬퍼 추가 — 기상/외출/귀가/지오펜스 전체 적용
  - CF 배포 완료 (4개 함수: pollDoorSensor, onIotWrite, checkDoorManual, girlfriendBotWebhook)
  - 헤드위그 봇: today doc flat 구조 읽기 수정
  - 앱 재설치 시 stale movement 복원 방지 (iot doc 날짜 검증)
  - today doc `_parseTodayData` 날짜 불일치 시 stale 데이터 무시
  - 데일리 로그 세그먼트 탭 → 시간 직접 편집 (Firestore 저장)
  - `OrderHabit.autoTrigger` 필드 추가 (wake/sleep → 습관 자동 완료)
  - NFC 기상/취침 시 매칭 습관 자동 체크

### 미커밋 파일
- 없음 (전체 커밋 + 푸시 완료)

### 미배포
- 없음 (CF 배포 완료, 앱 빌드 완료 — 폰 연결 후 `adb install -r build/app/outputs/flutter-apk/app-release.apk`)

### 다음 할 일
- [ ] 폰 연결 후 앱 설치 (`adb install -r`)
- [ ] 습관에 autoTrigger 설정 UI (습관 상세 화면에서 wake/sleep 선택)
- [ ] 오염된 Firestore 데이터 수동 정리 (study doc timeRecords 새벽 기록)
- [ ] 투두에서 진행도 목표 연결 UI (목표 선택 드롭다운)
- [ ] 경제학 등 신규 과목 로드맵 설정
- [ ] 크리쳐 알람 시스템 재설계

### 보류 작업
- 소설 「허락」 제1부 확장 (핸드오프: `assets/roadmap/HANDOFF_소설_허락_제1부.md`)

---

## 히스토리

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
