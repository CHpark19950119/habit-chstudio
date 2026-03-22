"""
배터리 매니저 — 20~80% 유지
뚜껑 닫힘 OR mmWave none → 배터리 관리 모드
뚜껑 열림 + 재실 → 항상 충전 ON
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

def tg(msg: str):
    try:
        requests.post(f"https://api.telegram.org/bot{TG_BOT}/sendMessage",
            json={"chat_id": TG_CHAT, "text": msg}, timeout=10)
    except:
        pass

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

def should_manage():
    """배터리 관리 모드 진입 조건: 뚜껑 닫힘 OR 방 비어있음"""
    lid = is_lid_open()
    home = is_home()
    if not lid:
        return True, "뚜껑 닫힘"
    if not home:
        return True, "외출"
    return False, ""

def check():
    b = psutil.sensors_battery()
    if b is None:
        return

    pct = b.percent
    manage, reason = should_manage()

    if not manage:
        # 사용 중 → 항상 충전
        if not plug_on:
            set_plug(True, f"사용 중 ({pct}%)")
        return

    # 관리 모드
    if pct >= HIGH:
        set_plug(False, f"{reason} — {pct}% >= {HIGH}%")
    elif pct <= LOW:
        set_plug(True, f"{reason} — {pct}% <= {LOW}%")
    else:
        state = "충전중" if b.power_plugged else "방전중"
        print(f"[Battery] {pct}% ({state}) — {reason}, 유지")

if __name__ == "__main__":
    print(f"배터리 매니저 시작 ({LOW}~{HIGH}%, {INTERVAL}초 간격)")
    print("관리 조건: 뚜껑 닫힘 OR 방 비어있음")
    plug_on = True
    try:
        while True:
            check()
            time.sleep(INTERVAL)
    except KeyboardInterrupt:
        print("\n종료. 충전 ON 복원.")
        set_plug(True)
