# Session Handoff
> 이 파일은 Claude Code 세션 간 작업 연속성을 위한 핸드오프 문서.
> session_save 호출 시 자동 업데이트됨. 다른 세션은 이 파일을 읽어 현재 상태를 파악한다.

## 마지막 세션
- **날짜**: 2026-03-31
- **시각**: 03:31
- **파일**: 2026-03-31_05.json

## 진행 중 작업
사용자 롤 게임 중.

## 미해결 이슈
- ElevenLabs Starter 크레딧 소진 (4/25 리셋)
- Tuya Cloud 쿼터 초과 (4/13 리셋) — CF 거짓 성공
- 에리카러스트 iPad Auto 화질 고정
- battery_manager pythonw 중복 실행 (시작 프로그램 등록 문제)

## 다음 할 일
- 커밋 (안정화 수정 전체)
- CF rolloverManual 테스트
- 웹페이지 리뉴얼
- 음성 비서 시스템 프로토타입
- 에리카러스트 화질 우회
- battery_manager 중복 실행 방지 (PID lock)
- 비바체 키오스크 IP (다음 방문 시)

## 이번 세션 요약
포트노이의 불평 1~10쪽 한국어 번역 HTML 완성 + 텔레 전송. 롤 프레임 최적화 (프로세스 정리 + RealTime 우선순위). WiFi 복구 후 전등 tinytuya 제어 성공. CF light 거짓 성공 피드백 기록.

## 결정사항
- CF light endpoint 완전 사용 불가 (거짓 성공 반환) — 어떤 상황에서도 시도 금지
- 롤 중 불필요 프로세스 적극 정리 OK
- 비코딩 작업은 터미널 세션이 적합
