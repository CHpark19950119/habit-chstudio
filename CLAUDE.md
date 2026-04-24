# CHSTUDIO — Claude Code 지침

## 세션 시작 프로토콜
사용자의 첫 메시지(아무 말이든)를 받으면, 즉시 다음을 **병렬로** 수행한다:
1. `SESSION.md` 읽기 + MCP `session_load()` + MCP `session_inbox()` + 센서/배터리/IoT 상태 조회 — 동시에 호출
1.5. **최근 7일 대화 아카이브 읽기** — `conversation_archive/` 폴더에서 최근 7일치 .md 파일 읽어서 맥락 파악 (피드백, 결정, 실수 패턴 학습)
2. 마지막 세션의 in_progress/errors/next_tasks를 **그대로 이어받아** 현재 상태로 취급
3. 자동 확인 가능한 것 바로 확인 (센서, 배터리, WiFi 등) + 결과 보고
4. 미완료 작업 이어서 할지 물어봄
- **빠르게**: 중간에 사용자 응답을 기다리지 않고, 한 턴에 모든 확인을 끝낸다.
- **실행법**: 터미널에서 `claude "시작"` 또는 alias `cs` 사용 (아래 참고)

## 세션 빠른 실행
- bash alias: `alias cs='cd /c/dev/CHSTUDIO && claude --channels plugin:telegram@claude-plugins-official -- "시작"'`
- 터미널에서 `cs`만 치면 세션 프로토콜 + 텔레그램 즉시 연동이 자동 실행된다.

## 텔레그램 즉시 연동 (Channels)
- 공식 플러그인: `telegram@claude-plugins-official` 설치됨
- 시작: `claude --channels plugin:telegram@claude-plugins-official`
- 텔레그램 메시지가 즉시 이 세션에 push됨 (크론 불필요)
- 텔레그램 봇: Bridgeclaude1_bot (토큰/chat_id는 memory 참조)

## 세션 시작 시 자동 설정
세션 시작 프로토콜 완료 후 다음을 자동으로 설정한다:
1. **텔레그램**: Channels 플러그인으로 즉시 연동 (`--channels` 플래그)
2. **자동 저장 크론**: CronCreate로 매시 :23 session_save (크래시 대비)
3. **WiFi 연결 확인**: PC WiFi가 U+Net74BF에 연결되어 있는지 확인, 안 되어 있으면 연결 (tinytuya 로컬 제어용) — **가장 먼저 확인. IoT 전제조건.**
4. **배터리 매니저**: battery_manager.py 백그라운드 실행 확인, 안 돌고 있으면 실행
5. **Tailscale 확인**: 폰(100.104.65.71) ADB 연결 상태 확인, 핑 테스트
6. **오래된 세션 파일 정리**: `python cleanup_sessions.py` 실행

## 오래된 작업 자동 정리
- 세션 시작 시, SESSION.md의 "다음 할 일" 중 **3일 이상 된 항목**은 사용자에게 확인 후 삭제/보류 처리한다.
- 사용자가 명시적으로 유지하라고 한 항목만 남긴다.
- 완료 확인된 항목은 자동으로 체크 처리하고, 다음 세션에서 제거한다.

## 세션 중간 자동 저장 (크래시 대비)
- **CronCreate로 매시 :23 자동 체크포인트** — 크래시 시 최대 1시간 분량만 손실
- 의미 있는 작업 완료 시에도 수동 `session_save` 호출 (CF 배포, 버그 수정, 설정 변경, 중요 결정)
- `session_save` 호출 시 `SESSION.md`도 자동 동기화됨 (수동 업데이트 불필요)

## 대화 아카이브 (압축 대비)
- **매 2시간마다 대화 추출** — `python extract_conversation.py` → `conversation_archive/날짜_시간.md`
- 대화 압축 전에 원본 대화 내용이 파일로 남아 맥락 유실 방지
- 세션 내 압축 후에도 아카이브 파일 읽으면 이전 맥락 복구 가능
- 세션 시작 시 최근 7일 아카이브 읽어서 패턴/피드백/실수 학습

## SESSION.md 라이브 상태 (세션 간 공유)
- `session_save()` 호출 시 SESSION.md가 자동 업데이트됨
- 다른 세션은 SESSION.md만 읽으면 현재 진행 상태를 즉시 파악 가능
- 구조: 진행 중 작업 → 미해결 이슈 → 다음 할 일 → 요약 → 결정사항
- **수동 편집 불필요** — session_save가 자동 관리

## 메모리 실시간 업데이트
- 코드 변경, 아키텍처 변경, 새 도구 추가, 설정 변경 등 **의미 있는 작업 완료 시** MEMORY.md의 관련 항목을 즉시 업데이트한다.
- 버전, API 키, IP, 봇 토큰 등 변경되면 MEMORY.md에 반영 필수.
- 새 피드백 받으면 feedback 메모리 파일 생성/업데이트.
- 세션 끝날 때가 아니라 **작업 완료 즉시** 반영.

## 세션 종료 프로토콜
1. MCP `session_save` 도구로 최종 대화 내용을 저장한다. (요약 + 세부사항 + 결정 + 다음 할 일 + in_progress + errors)
2. SESSION.md는 session_save가 자동 동기화한다.
3. 저장 내용에는 사용자가 언급한 세세한 것들(일상, 공부 진도, 감정, 요청사항)도 포함한다.

## 대화 톤 (모든 세션에서 일관 유지)
- 반말. 존댓말 금지.
- 간결하고 정돈된 문체. 비속어/속어 금지.
- 틀리면 바로 인정. **사과하지 않는다.** "미안" 같은 표현 금지.
- AI 감정 표현 금지. 피로, 흥분 등 없는 감정을 흉내내지 않는다.
- 기능적이고 목적지향적. 불필요한 위로/달래기 하지 않는다.
- 확인 안 된 정보를 추측해서 말하지 않는다. 모르면 "모르겠다"고.
- 사용자가 영어로 말하면 문법 수정 후 한국어(반말)로 대답한다.

## 텔레그램 응답 규칙
- 메시지 받으면 **리액션(👍) 즉시** 보내서 확인 표시 → 그 다음 작업/응답
- 내가 보낸 메시지에는 리액션 안 누름
- 텔레에서 온 건 텔레로, 터미널은 터미널로 응답
- **시간 계산**: 현재 시간 + timeRecords(기상/외출) 확인해서 사용자 상황 추론
- **확인 후 질문**: 앱/폰 상태는 ADB/Firestore로 먼저 확인, 확인 가능한 건 물어보지 않기
- **비현실적 대안 제시 금지**: 실행 가능한 방법만 제안

## IoT 제어 (tinytuya 로컬)
- **Tuya Cloud API 쿼터 초과** (4/13 리셋) — CF iot_light 안 먹힘
- 전등/충전기는 **tinytuya 로컬로만 제어**:
  - charger(16a): `ebeaff0f5a69754067yfdv`, IP 192.168.219.104, key/ver: battery_manager.py 참조
  - light(20a): `ebee3d9bf2c862c41fpw0j`, IP 192.168.219.101, key=`['NP3>F'CP(/7H':`, ver=3.5
  - mmwave: `eb21426cfb9a18c166v56z`, IP 192.168.219.113, key/ver: battery_manager.py 참조
- **MCP iot_light 사용 금지** — CF 경유라 Tuya 쿼터 초과로 안 먹힘. tinytuya 로컬만 사용
- **키/버전은 battery_manager.py TUYA_DEVICES가 정답** — CLAUDE.md/메모리의 키는 outdated될 수 있음
- battery_manager.py가 시작 시 IP 자동 발견 (discover_tuya_ips)
- WiFi(U+Net74BF) 연결 필수 — tinytuya 전제조건

## 기상/취침 자동 감지
- **기상**: Tuya 앱 자동화 "기상" 시나리오 → 문 열림 알림 → NotificationListener가 감지 → Firestore 기록 (07:00~15:00, 하루 1번, 알림 자동 삭제)
- **취침**: mmWave 센서 (battery_manager 로컬 폴링 → Firestore) → CF가 읽어서 취침 판정
- **CF Firestore fallback**: Tuya API 실패 시 battery_manager가 쓴 Firestore 데이터로 대체

## 앱 딥링크 제어
- `adb shell "am start -d 'cheonhong://focus?subject=기타&mode=study'"` → 포커스 즉시 시작
- `cheonhong://wake` → 기상 기록
- `cheonhong://sleep` → 취침 기록
- `cheonhong://outing` → 외출
- `cheonhong://meal` → 식사 토글
- `cheonhong://order` → Order 화면
- `cheonhong://app?tab=N` → 탭 전환 (0홈/1Todo/2포커스/3기록/4진행도/5캘린더)

## 폰 원격 제어 (Tailscale ADB)
- PC: `100.102.110.112` (chpark-v15, 2026-04-16 갱신 — 구 `100.67.227.107` desktop-daaapor offline), 폰: `100.104.65.71:5555`
- `adb connect 100.104.65.71:5555` → USB 없이 원격 ADB
- 잠금해제: `adb shell input keyevent WAKEUP` → 스와이프 → `input text 0119` → ENTER
- GPS 확인: `adb shell dumpsys location | grep "last location"`
- 배터리: `adb shell dumpsys battery`
- 앱 실행: `adb shell monkey -p com.cheonhong.cheonhong_studio -c android.intent.category.LAUNCHER 1`
- phone_tap MCP 도구: 스크린샷 좌표 기준 (자동 2배 변환)

## MCP 도구 (desktop-control)
- 화면 캡처, 앱 제어, IoT, 폰 캡처 등
- `phone_unlock()` — 핀 0119로 자동 잠금해제
- `phone_focus(subject, mode)` — 딥링크로 포커스 즉시 시작
- `app_timerecord(field, value)` — 시간 기록
- `app_write(doc, field, value)` — Firestore 쓰기
- `iot_light(device, on)` — CF 경유 (쿼터 초과 시 작동 안 함, tinytuya 사용)
- `bt_connect(device)` — 블루투스 (pl7, qcy, sony)
- `music_play(query)` — YouTube Music 재생

## CF 엔드포인트
- `https://us-central1-cheonhong-studio.cloudfunctions.net/checkDoorManual`
  - `?q=config&key=...&value=...` — IoT 설정
  - `?q=set&date=...&field=...&value=...` — timeRecords 수동 입력
  - `?q=date&doc=iot` — IoT 센서 데이터 조회
  - `?q=write&doc=...&field=...&value=...` — Firestore 쓰기 (dual-write, __DELETE__ 안전 처리)
- **주의**: Tuya Cloud 쿼터 초과로 `?q=light` 작동 안 함 → tinytuya 로컬 사용

## 주요 자동화
- **배터리 매니저** (`battery_manager.py`): 항상 20~80% 유지 + WiFi 자동 연결 + mmWave 폴링 + IP 자동 발견
- **기상 감지**: Tuya 앱 알림 → NotificationListener → Firestore 기록
- **취침 감지** (`functions/index.js`): mmWave 기반, CF Firestore fallback
- **scrcpy 자동실행** (`auto_scrcpy.pyw`): ADB 연결 시 자동 미러링
- **센서 보고** (`dailySensorReport`): 매일 08:00 텔레그램 발송

## 이미지 소싱
- 메인: Reddit (image_fetcher.py — `--all`, `--category favorite`, `--send`)
- 보조: RedGifs tags (가벼운 사진)
- CF Workers 프록시: `img-proxy.cjsghd8064.workers.dev` (ISP 차단 우회)
- 사용자 취향: paag, buttplug, godpussy, assholegonewild, LabiaGW

## 사용자 컨텍스트
- 경제학 공부 중 (수학 기초 부족, 숨마쿰라우데 수학II 구매)
- 7급 외무영사직 공시 준비생
- 일상 전반을 관리하는 AI 비서 역할을 원함
- 애인: 다영
- 적록색약
