# CHEONHONG STUDIO — CHANGELOG

## 현재 이슈
- [ ] 4AM 일전환(rollover) 정상 작동 확인
- [ ] Phase C today/history 문서 동기화 확인

---

## 2026-03-13

### v10.8.3 — 🦉 헤드위그 (텔레그램 위치 봇) + Wake 시간대 설정

#### 헤드위그 봇 (`functions/index.js`)
- [x] girlfriendBotWebhook: "위치/어디/어디야/where/뭐해" 키워드 즉시 응답
- [x] CF만으로 완결 (앱 GPS 대기 없음, Firestore 상태 기반 즉시 판단)
- [x] 상태 판단: 수면💤 / 기상직후☀️ / 방금외출🧹💨 / 외출중🧹 / 집🏰
- [x] 외출 시 Google Maps 링크 + 지도 핀 자동 전송
- [x] 키워드 외 메시지 → "어디야로 물어봐주세요" 안내
- [x] locationResponseTrigger 삭제 (불필요)

#### 외출 시 GPS 저장 (`door_sensor_service.dart`)
- [x] 문 열림(door open) 감지 시 GPS 1회 획득
- [x] Firestore `data/iot` lastLocation 필드 저장 (latitude, longitude, updatedAt)
- [x] LocationService.getPositionWithFallback(): high → lastKnown → low accuracy

#### 정리
- [x] LocationRequestService → 빈 스텁 (헤드위그 대체)
- [x] CF 배포 + 웹훅 설정 + APK 설치 완료
- [x] 테스트: "어디야" → 🧹💨 방금 나갔어요! 즉시 응답 확인

#### Wake 시간대 설정 (`wake_service.dart` + `settings_screen.dart`)
- [x] 기본 시간대: 6:30AM~1:00PM (기존 4AM~12PM에서 변경)
- [x] 앱 내 TimePicker로 시작/종료 시간 변경 가능
- [x] SharedPreferences `wake_start_min`/`wake_end_min` 저장

---

### v10.8.2 — Wake 디버그 모드 + 설정 UI

#### Wake 디버그 모드 (`wake_service.dart`)
- [x] `debugMode` 플래그: 4AM~12PM 시간 조건 우회
- [x] SharedPreferences `wake_debug_mode` 저장

#### 설정 화면 (`settings_screen.dart`)
- [x] 기상 감지 카드: 모드 전환 칩 (센서/수동)
- [x] 디버그 모드 토글 (센서 모드일 때만 표시)
- [x] 모드별 설명 텍스트

---

### v10.8.1 — Tuya 도어센서 연동 + Wake 자동 감지

#### Cloud Functions (`functions/index.js`)
- [x] Tuya API 폴링 (1분 간격) → Firestore `data/iot` door 필드 기록
- [x] 필드: state(open/closed), isOpen, sensorId, lastChanged, lastPolled
- [x] checkDoorManual: 수동 테스트 HTTP 엔드포인트

#### SensorWakeDetector (`wake_service.dart`)
- [x] DoorSensorService eventStream 구독
- [x] 4AM~12PM 문 열림 시 자동 기상 감지 (하루 1회)
- [x] WakeService.recordWake() → NFC FSM wake 트리거
- [x] WakeService.init(): SharedPreferences wake_mode (sensor/manual)
- [x] WakeService.setMode(): 런타임 모드 전환

#### DoorSensorService 연동
- [x] CF 필드 → DoorEvent.fromMap 호환 (state + sensorId)
- [x] DoorSensorService 자동 활성화 (sensor 모드 시)
- [x] app_init.dart Phase 4에 WakeService().init() 추가

---

### v10.8.0 — V11 로드맵 + 소설 v4 대규모 업데이트

#### V9 → V11 로드맵 마이그레이션 (`roadmap_data.json`, `roadmap_models.dart`, `order_life_tab.dart`)
- [x] 10탭 → 12탭: 거주지 아카이브, 인터넷 여성들, 2017~18 전수 추가 / 그들과 나 제거
- [x] 6개 신규 모델 클래스: HomeCard, InternetWoman, DetailEntry, DetailTransactions, Discovery13Section, CivilServiceMotivation
- [x] PsychAnalysis 확장: discovery13HealPattern, civilServiceMotivation, sexCoexistenceMap
- [x] Economy 확장: incomeHistory, dayoungBypass, pcBang
- [x] JSON 데이터 893줄, 13개 탑레벨 키, 합격자 비교(compare) 제거

#### 소설 뷰어 v4 전면 재작성 (`novel_viewer_screen.dart`)
- [x] 60KB → 952KB (v1→v4), 11챕터 네비게이션
- [x] 커버 페이지 + 다크 그라디언트
- [x] 신규 블록: data-card, analysis-panel(접기), circuit, photo-illust, section-break, record-card
- [x] 스크롤러블 탭바 + balanced-div HTML 파서
- [x] APK 83.2MB

---

### v10.7.2 — 목표·습관 시스템 전면 재설계

#### 목표 관리 v6 (`order_goals_tab.dart` — 전면 재작성)
- [x] 중장기 목표 전용 화면: 제목 + 마감일(DatePicker) 2필드
- [x] 체크리스트 기반 자동 진도 (수동 % 입력 제거)
- [x] 마감순 자동 정렬 + D-Day 색상 (7일 이내 amber, 당일 red)
- [x] 완료 아카이브 접기/펼치기
- [x] 목표 상세: 체크리스트 추가/삭제/토글 + 완료 처리/편집/삭제

#### 습관 간소화 (`order_goals_tab.dart` 통합)
- [x] 5단계(집중/대기/미지정/정착/보관) → 2단계(활성/완료)
- [x] 랭크/큐/자동승급 UI 제거
- [x] 탭 체크 + 스트릭 카운트 + 성장이모지
- [x] 롱프레스 상세: 현재연속/최고기록/성장 + 보관/삭제

#### Order 커맨드센터 간소화 (`order_screen.dart`)
- [x] TARGETS: priority 기반 → 마감순 자동 정렬 (상위 3개)
- [x] DISCIPLINE: 큐/정착 표시 제거, 활성 습관만 체크리스트
- [x] Quick Access: 4버튼 → 3버튼 (목표·습관 통합)
- [x] blobCtrl 미사용 애니메이션 제거

#### 죽은 코드 제거 (`order_models.dart`)
- [x] StressLog 클래스 + 관련 enum 3개 제거
- [x] SetbackLog 클래스 + 관련 enum 제거
- [x] ExamTicketInfo 클래스 제거
- [x] OrderData에서 stressLogs/setbacks 직렬화 제거
- [x] APK 크기 82.7MB → 82.4MB (0.3MB 감소)

---

### v10.7.1 — 기록 탭 차트 모션 + 비용 분리 + 버그 수정

#### 기록 탭 모션 리디자인 (`statistics_screen.dart`)
- [x] 임베디드 모드 4섹션 구조: ① 오늘 요약, ② 추이, ③ 과목 분석, ④ 집중도
- [x] `_embeddedSectionLabel()` 섹션 헤더 (이모지 + 라벨 + 구분선)
- [x] 중복 카드 제거 (studySummaryCard, donutCard)
- [x] 세션별 집중도 — 프로그레스바 `_chartAnim` 애니메이션
- [x] 시간별 집중도 — 바 높이/투명도 `_chartAnim` 연동
- [x] 수면 패턴 — 기상 트렌드 바 성장 + 라벨 페이드인
- [x] 1차/2차 비율 바 — `AnimatedBuilder` 비율 애니메이션

#### Order 비용 분리 (`order_screen.dart`, `order_expense_tab.dart`)
- [x] AI 비용 전용 행 (`_aiCostRow`) — `₩X,XXX (+₩last)` + [+] 퀵입력
- [x] VAULT 헤더: 📚 수험 / 🤖 AI 개별 통계 + 합계
- [x] 비용 즉시 반영 — `await showModalBottomSheet<int>()` 패턴

#### 버그 수정
- [x] `nfc_screen.dart`: ChangeNotifier 패턴으로 전환 (onStateChanged → addListener)
- [x] `plan_service.dart`: planDocPath 제거 대응 (로컬 uid + 직접 경로)
- [x] `roadmap_models.dart`: `_toInt()` 헬퍼로 String→int 런타임 크래시 수정

---

## 2026-03-12

### v10.7.0 — V9 인생 로드맵 + 소설 탑재 + 홈 모션 고급화

#### 인생 로드맵 V9 (`order_life_tab.dart`, `roadmap_models.dart`, `roadmap_data.json`)
- [x] V9 HTML 기준 전면 재작성: 10탭 체계
  - 통합 타임라인 / 연애사 / 심리 분석 / 공시 분석 / 그들과 나 / 경제활동 / 성적 기록 / 육성 기록 / 소설 콘티 / 미완료 과제
- [x] **그들과 나** (V9 핵심): 합격자 9명 개별 정밀 해부
  - 고나연/강민우/이혜린/신재훈/이지연/권대일/황정규/정영미/서영제
  - 각 합격자별: 점수 추이, 냉철한 단점 지적, 천홍이 가져갈 것
  - 종합 비교표 (출발점/수험기간/고시반/PSAT/약점)
  - 전환점 비교표, 방법론 갭 분석표
- [x] **심리 분석 확장**: 허락의 천장 + 확신의 소멸 + 성욕과 공존하는 공부 4원칙
- [x] **공시 분석 확장**: 이중 진단(방법+허락) + 경로A/B + 편입복제 조건 + 능력 증거
- [x] V9 HTML 에셋 원본 탑재 (`assets/roadmap/박천홍_인생로드맵_v9.html`)

#### 소설 「허락」 제1부 탑재 (`novel_viewer_screen.dart`)
- [x] `assets/roadmap/novel_part1.html` (60KB) — 제1부: 흙 (1995~2018)
- [x] HTML 파싱 → Flutter 네이티브 위젯 렌더링 (외부 의존성 없음)
- [x] 커버/챕터/산문/인용/기록카드/분석패널/회로시각화 등 20개 블록 타입
- [x] 소설 콘티 탭에 "소설 원문 읽기" 버튼 추가 → 전체 화면 뷰어

#### 홈 탭 전환 모션 고급화 (`home_screen.dart`)
- [x] IndexedStack 위에 페이드+슬라이드 트랜지션 레이어
- [x] 200ms 부드러운 전환 (fadeOut → switch → fadeIn)
- [x] 햅틱 피드백 (selectionClick) 추가
- [x] 하단 내비 선택 인디케이터 바 애니메이션

#### Todo 주간 차트 애니메이션 (`home_todo_section.dart`)
- [x] 바 차트 800ms 성장 애니메이션 (easeOutCubic)
- [x] 7개 바 스태거 효과 (순차 등장)

---

## 2026-03-11

### v10.6.0 — 인생 로드맵 v6.1 + 수면 자동 감지
- [x] 9탭 완전 리빌드 (타임라인~미완료 과제)
- [x] 모델 v6.1: 13개 신규 클래스
- [x] 수면 자동 감지: BroadcastReceiver + AlarmManager + NFC FSM 연동

### v10.5.0~v10.5.2 — 인생 로드맵 v5 + 서비스 대규모 추가
- [x] HTML v5→v6.1 3단계 진화 (6탭→9탭)
- [x] 문감지 센서 / 자동 백업 / 일일·주간 리포트
- [x] 웹앱 아카이브 디자인 개선

### v10.5.0 — 서비스 대규모 추가 (문감지/백업/리포트)

#### 문감지 센서 준비 (`door_sensor_service.dart` + `iot_models.dart`)
- [x] Firestore `data/iot` 문서 실시간 리스너
- [x] DoorEvent 모델 (open/closed/unknown, timestamp, sensorId)
- [x] IoTDeviceStatus 모델 (확장용)
- [x] 30초 디바운스, DayState FSM 연동 Telegram 알림
- [x] `simulateEvent()` 테스트 메서드
- [x] SharedPreferences 설정 (enabled, debounce)

#### 자동 백업 서비스 (`backup_service.dart`)
- [x] **autoBackup()**: 취침 시 자동 실행, 1일 1회 제한
  - today/study/liveFocus/history/nfcTags/memos 수집
  - 로컬 JSON 파일 저장 (`backups/backup_yyyy-MM-dd_HHmm.json`)
  - 최근 7개 유지, 오래된 백업 자동 삭제
  - Telegram 완료 알림
- [x] **exportAll()**: 수동 전체 내보내기 (3개월 히스토리 + NFC 이벤트)
- [x] **restoreFromBackup()**: 로컬 백업에서 Firestore 복원
- [x] Timestamp → ms 재귀 변환 (`_sanitize`)

#### 일일/주간 리포트 서비스 (`report_service.dart`)
- [x] **일일 리포트** (취침 시 자동 Telegram)
  - 활동시간, 순공시간, 식사, 외출, 투두 완료율, 습관, 포커스 세션
  - 격려 메시지 (성과 기반)
- [x] **주간 리포트** (매주 일요일 자동)
  - 7일 총공부/일평균, 최다/최소일, 트렌드(전주 대비)
  - 투두 완료율, 습관 스트릭 top3, 식사 패턴, 기상/취침 평균
  - 미니 바 차트
- [x] `checkWeeklyReport()` 앱 시작 시 자동 체크

#### 앱 통합
- [x] NFC 취침 핸들러: 3초 후 일일리포트 + 자동백업 비동기 실행
- [x] AppInit: DoorSensorService.init() + ReportService.checkWeeklyReport()

#### 웹앱 아카이브 디자인 개선
- [x] 카드 그림자 + hover 효과 + fadeSlide 애니메이션
- [x] 스켈레톤 로딩, empty state, toast
- [x] blur backdrop 헤더, 모달 개선
- [x] 기존 사이트(index.html) 스타일과 통일

### v10.4.3 — 버스 도착정보 + 홈 상단 버튼
- [x] **BusService**: 경기도 GBIS v2 API 연동 (`bus_service.dart`)
  - 정류장: 금강4단지(26411), 송정마을(26023)
  - 5분 주기 폴링: 기상→시작, 외출/공부→중단
  - 텔레그램 전송: 노선명, 도착예정시간, 정거장 수, 잔여좌석
  - `fetchNow()` 공개 메서드 — 수동 즉시 조회
- [x] **방향 구분**: routeDestName 기반 방향별 그룹핑
  - 🚉 대야미역(송정초) 방면
  - 📚 도서관(차고지) 방면
  - 🏙️ 서울 방면
- [x] **NFC FSM 연동**: wake→startPolling, outing/study→stopPolling
- [x] **홈 상단 아이콘 버튼**: NFC | 버스 | 메모 | 설정 (4개, 헤더 우측)
  - 하단 퀵툴 영역 제거 → 상단으로 통합

---

## 2026-03-10

### v10.4.1 — 웹앱 아카이브 페이지 + 기존 페이지 보존
- [x] **기존 페이지 100% 보존**: life/study/goals/mind + 30개 JS + 6개 CSS 그대로
- [x] **archive.html 신규**: 앱 데이터 대시보드/기록/ORDER/백업 4탭
  - Firebase Auth (Google) + Firestore 직접 연결
  - 인메모리 캐시 (30초 TTL, DocCache) — 중복 Firestore 읽기 방지
  - Set 기반 streak 계산 (O(1) lookup)
  - history → archive → study doc 3단 fallback
  - JSON 접기/펼치기 (대용량 데이터 lazy rendering)
  - archive doc 브라우저 추가
  - ORDER dual-write (study + today doc)
- [x] **index.html**: 아카이브 네비 카드 추가 (기존 4개 + 1개)
- [x] **Pretendard 폰트**: 기존 사이트와 일관된 미니멀 스타일

### v10.4.0 — ORDER v5 리빌드 + HOME 대시보드 재구성

#### ORDER v5 — 단일 커맨드 센터
- [x] **4탭 제거**: IndexedStack → 단일 ListView
- [x] **MISSION 카드**: 현재 기간(StudyPlanData) + 서브기간 + 오늘 계획 + 진행률
- [x] **TARGETS 섹션**: 1순위/2순위 목표 + 프로그레스 + D-day
- [x] **DISCIPLINE 섹션**: 집중 습관 원터치 완료 + 대기열 프리뷰 + 정착 배지
- [x] **OVERVIEW 행**: 평균 스트릭 / 목표 달성 / 수험 비용 3칩
- [x] **QUICK ACCESS**: 목표관리/습관관리/회계장부 → 별도 풀스크린 페이지로 push

#### HOME 대시보드 v2 — 그룹핑 재구성
- [x] **STATUS 그룹**: NFC 루틴 → 순공시간|성적 (2열) → 도서관 → 포커스배너
- [x] **TODAY 그룹**: 섹션 헤더 + COMPASS 포탈
- [x] **LOG 그룹**: 메모 → 데일리로그 → 도구
- [x] **순공시간/성적 카드 컴팩트화**: 세로형 레이아웃, 2열 Row에 최적화

### v10.3.4 — 선호 좌석 확인 + COMPASS FAB 아이콘
- [x] **COMPASS FAB**: `C` 텍스트 → `explore_rounded` 나침반 아이콘
- [x] **선호 좌석 기능**: 부곡도서관 내 자리 상태 즉시 확인
  - 홈 도서관 카드에 선호 좌석 상태 행 (초록=빈자리, 빨강=사용중)
  - `좌석설정` 버튼 → 다이얼로그에서 좌석번호 입력 (쉼표 구분, 최대 5개)
  - `LibraryService.getFavSeats/setFavSeats` — SharedPreferences 저장

### v10.3.3 — ORDER 플로팅 스위칭 + 텔레그램 한국어 수정
- [x] **주간 히트맵 제거**: 습관탭 `_weekHeatmap()` + 통계탭 `_heatmap()` 삭제
- [x] **홈↔ORDER 플로팅 스위칭**: Order는 독립 공간 유지, FAB으로 즉시 전환
  - 홈 대시보드: COMPASS FAB (인디고) → Order 진입 (슬라이드 트랜지션)
  - Order 화면: 홈 FAB → Navigator.pop 홈 복귀
  - COMPASS 칩 탭도 유지 (200ms 페이드)
- [x] **텔레그램 한국어 수정**: form-urlencoded → JSON+UTF-8 (telegram_service + weather_service)

### v10.3.2 — 진행도 1차/2차 분리 + 통계 라운드 비율
- [x] **진행도 화면 1차/2차 분리**: 라운드 필터 (전체/1차 PSAT/2차 전공) + 요약 카드
- [x] **통계 1차/2차 비율 카드**: 비율 바 + 시간 + % + 과목별 세부 (기록탭)
- [x] **2차 과목 추가**: 경제학/국제법/국제정치학 (SubjectConfig + BotanicalColors + ProgressScreen)
- [x] **SubjectConfig.examRound()**: 과목→시험 라운드 분류 (1차/2차/공통)

### v10.3.1 — 투두 버그수정 + NFC→직접토글 전환
- [x] **투두 빨간화면 수정**: `_showTodoStatsSheet` Map 캐스팅 크래시 (`Map.from()` 안전 캐스팅)
- [x] **copyWith null 클리어**: `clearSubject`/`clearPriority`/`clearType`/`clearEstimatedMinutes` 플래그
- [x] **루틴 타일 직접 토글**: 공부(시작/종료), 취침(자동 공부종료), 식사(NFC 위임)
- [x] **_editTodoItem 분리**: home_screen → home_todo_section (관심사 분리)
- [x] **estimatedMinutes 표시 수정**: `!` 연산자 누락

### v10.3 — Wake Toggle + Todo Enhancement + Order Rebuild
- [x] Wake Service + 탭 기상 기록
- [x] 투두 과목태그(5과목) + 우선순위 + 예상시간 + 수정시트
- [x] Order 탭: Goals/Habits/Expense/Life Path (Today/Stats 제거)
- [x] 캘린더 투두 완료율 dot (Green/Amber/Red)

### v10.2 — NFC DayState FSM + Geofence
- [x] **DayState enum**: idle/awake/outing/studying/returned/sleeping
- [x] **식사 독립**: eating 제거 → `_isMealing` boolean
- [x] **Geofence**: 3분 GPS, 150m 반경, 2회 연속 확인 → 자동 외출/귀가
- [x] **Stream 플리커 수정**: 스트림에서 timeRecords 파싱 제거 (today doc only)

### v10.0 — NFC DayState FSM 리빌드
- [x] boolean 토글 → 6상태 FSM, 태그 30초 쿨다운
- [x] 자동 기상, 리마인더, 일일 요약 Telegram
- [x] GeofenceService (집 위치 자동 외출/귀가)

---

## 2026-03-09
### v9.13 — 캐시 동기화 버그 수정
- [x] bgRefresh write-protect 가드, updateTimeRecord await 수정, write-protect 10초

## 2026-03-08
### v9.12 — 기록탭 강화 + 포커스존 즉시 돌입
- [x] 순공시간 추이 LineChart + 과목별 BarChart + SubjectConfig Firestore sync
- [x] 포커스존: 과목→모드→시작→FocusScreen 직행

### v9.10 — 홈 대시보드 정리 + 도서관 배치도
- [x] Habitat FAB 비활성화, 대시보드 순서 재배치
- [x] 도서관 84석 CustomPainter 배치도 (핀치줌, 탭 말풍선, 60초 자동갱신)

### v9.6 — 부곡도서관 좌석 현황
- [x] HTTP 크롤링 + 30초 캐시, 홈 카드 + 배치도 화면

### v9.5 — 통계 집중도 + Cradle 각도 기반
- [x] 세션별/시간별 집중도, 거치대 각도 감지 (dot product, 12°/25° 히스테리시스)

### v9.4 — Focus Zone 3-View Rewrite
- [x] Hive-first 데이터 흐름, 글래스모피즘 3-View, 세션 삭제

### v9.2 — Glassmorphism Remodel
- [x] Focus + Todo + Progress 전면 글래스모피즘 적용

### v9.0 — NFC/Focus ChangeNotifier 전환
- [x] NFC/Focus Service → ChangeNotifier + ListenableBuilder

---

## 2026-03-07 이전 (요약)
- **v6.0** Phase C: Today + Monthly History 아키텍처
- **v5.x** Study Creature (Flame) + Habitat + 스프라이트
- **v4.x** 3-layer 캐시 + _safeSetState + Optimistic UI
- **v3.x** Phase B 문서 분리 + 캘린더 안정화
- **Phase 1-5 정리**: 4,500줄 삭제 (10개 서비스), firebase_service 4분할

---

## 참조

### Firestore 문서 구조 (Phase C)
| 문서 | 필드 | 크기 |
|------|------|------|
| data/today | date, timeRecords, studyTime, todos, orderData | ~2KB |
| data/study | timeRecords, studyTimeRecords, focusCycles, todos, orderData | ~50KB |
| data/creature | creature data | ~1KB |
| data/liveFocus | 실시간 포커스 | ~1KB |
| history/{yyyy-MM} | month, days.{dd}, summary | ~7KB/월 |
| archive/{yyyy-MM} | timeRecords, studyTimeRecords, focusCycles, todos | ~10KB/월 |

### 로그 키워드
`[Home]` 홈 로드 · `[FB]` Firestore · `[LocalCache]` Hive · `[Telegram]` 알림 · `[Rollover]` 4AM 일전환 · `[Archive]` 월별 아카이브
