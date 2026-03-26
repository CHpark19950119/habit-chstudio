"""
배터리 매니저 — 20~80% 유지
뚜껑 닫힘 OR mmWave none → 배터리 관리 모드
뚜껑 열림 + 재실 → 항상 충전 ON
게임 실행 중 → 항상 충전 ON
"""
import time
import ctypes
import psutil
import requests

CF_URL = "https://us-central1-cheonhong-studio.cloudfunctions.net/checkDoorManual"
TG_BOT = "8514127849:AAF8_F7SBfm51SGHtp9X5lva7yexdnFyapo"
TG_CHAT = "8724548311"
LOW = 20
HIGH = 80
INTERVAL = 300  # 5분

plug_on = None
_last_sync = 0
SYNC_INTERVAL = 600  # 10분마다 실제 플러그 상태 동기화

# 게임 프로세스 목록 (소문자)
GAME_PROCESSES = {
    # 게임 감지 비활성화 — 수동 제어
    "tft.exe",
}

def tg(msg: str):
    try:
        requests.post(f"https://api.telegram.org/bot{TG_BOT}/sendMessage",
            json={"chat_id": TG_CHAT, "text": msg}, timeout=10)
    except:
        pass

def get_actual_plug_state():
    """Firestore에서 실제 20a 플러그 상태 조회"""
    try:
        r = requests.get(f"{CF_URL}?q=light&device=20a", timeout=15)
        data = r.json()
        return data.get("light", "").upper() == "ON"
    except:
        return None

def sync_plug_state():
    """실제 플러그 상태와 plug_on 변수 동기화"""
    global plug_on, _last_sync
    now = time.time()
    if now - _last_sync < SYNC_INTERVAL:
        return
    _last_sync = now
    actual = get_actual_plug_state()
    if actual is not None and actual != plug_on:
        print(f"[Sync] 플러그 상태 불일치 — 스크립트: {plug_on}, 실제: {actual} → 동기화")
        plug_on = actual

def set_plug(on: bool, reason: str = ""):
    global plug_on
    if plug_on == on:
        return
    try:
        r = requests.get(f"{CF_URL}?q=light&on={'true' if on else 'false'}&device=20a", timeout=15)
        plug_on = on
        msg = f"🔋 충전 {'ON' if on else 'OFF'}"
        if reason:
            msg += f" — {reason}"
        print(f"[Plug] {msg}")
        tg(msg)
    except Exception as e:
        print(f"[Plug] error: {e}")

def is_lid_open():
    """모니터 개수로 뚜껑 감지 — 0이면 닫힘"""
    try:
        return ctypes.windll.user32.GetSystemMetrics(80) > 0
    except:
        return True

def is_home():
    """mmWave 센서로 재실 확인"""
    try:
        r = requests.get(f"{CF_URL}?q=date&doc=iot", timeout=15)
        data = r.json()
        state = data.get("presence", {}).get("state", "none")
        return state != "none"
    except:
        return True

def is_gaming():
    """게임 프로세스 실행 중인지 확인"""
    try:
        for p in psutil.process_iter(["name"]):
            if p.info["name"] and p.info["name"].lower() in GAME_PROCESSES:
                return True
    except (psutil.NoSuchProcess, psutil.AccessDenied):
        pass
    return False

def should_manage():
    """배터리 관리 모드: 항상 20~80% 유지 (게임 중만 예외)"""
    if is_gaming():
        return False, "게임 중"
    return True, ""

def heartbeat(pct, plugged, gaming):
    """Firestore에 heartbeat 전송 — CF 안전장치용"""
    try:
        requests.get(
            f"{CF_URL}?q=config&key=batteryHeartbeat&value={int(time.time())}",
            timeout=10)
        requests.get(
            f"{CF_URL}?q=config&key=batteryPercent&value={pct}",
            timeout=10)
        requests.get(
            f"{CF_URL}?q=config&key=batteryPlugOn&value={'true' if plugged else 'false'}",
            timeout=10)
    except:
        pass

def check():
    b = psutil.sensors_battery()
    if b is None:
        return

    pct = b.percent
    manage, reason = should_manage()
    gaming = is_gaming()

    # 주기적으로 실제 플러그 상태와 동기화
    sync_plug_state()

    # heartbeat 전송
    heartbeat(pct, plug_on, gaming)

    if not manage:
        # 게임 중 → 항상 충전
        if not plug_on:
            set_plug(True, f"게임 중 ({pct}%)")
        return

    # 관리 모드
    if pct >= HIGH:
        set_plug(False, f"{pct}% >= {HIGH}%")
    elif pct <= LOW:
        set_plug(True, f"{pct}% <= {LOW}%")
    else:
        state = "충전중" if b.power_plugged else "방전중"
        print(f"[Battery] {pct}% ({state}), 유지")

if __name__ == "__main__":
    print(f"배터리 매니저 시작 ({LOW}~{HIGH}%, {INTERVAL}초 간격)")
    # 시작 시 실제 플러그 상태 확인
    actual = get_actual_plug_state()
    if actual is not None:
        plug_on = actual
        print(f"플러그 초기 상태: {'ON' if plug_on else 'OFF'} (실제 조회)")
    else:
        plug_on = True
        print("플러그 초기 상태: ON (조회 실패, 기본값)")
    _last_sync = time.time()
    try:
        while True:
            check()
            time.sleep(INTERVAL)
    except KeyboardInterrupt:
        print("\n종료. 충전 ON 복원.")
        set_plug(True)
