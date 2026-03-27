"""
배터리 매니저 — 20~80% 유지 (tinytuya 로컬 제어)
뚜껑 닫힘 OR mmWave none → 배터리 관리 모드
뚜껑 열림 + 재실 → 항상 충전 ON
게임 실행 중 → 항상 충전 ON
"""
import time
import ctypes
import psutil
import requests
import tinytuya

CF_URL = "https://us-central1-cheonhong-studio.cloudfunctions.net/checkDoorManual"
TG_BOT = "8514127849:AAF8_F7SBfm51SGHtp9X5lva7yexdnFyapo"
TG_CHAT = "8724548311"
LOW = 20
HIGH = 80
INTERVAL = 300  # 5분

plug_on = None
_last_sync = 0
SYNC_INTERVAL = 600  # 10분마다 실제 플러그 상태 동기화


# ═══ Tuya 로컬 제어 설정 ═══
# 20a(ebee3d9bf2c862c41fpw0j, 101) = 전등 (스탠드)
# 16a(ebeaff0f5a69754067yfdv, 104) = 충전기
TUYA_DEVICES = {
    "charger": {"id": "ebeaff0f5a69754067yfdv", "ip": "192.168.219.104", "key": ">|(blpf;WLCPsLq&", "ver": 3.5},
    "light":   {"id": "ebee3d9bf2c862c41fpw0j", "ip": "192.168.219.101", "key": "['NP3>F'CP(/7H':", "ver": 3.5},
    "mmwave":  {"id": "eb21426cfb9a18c166v56z", "ip": "192.168.219.113", "key": "uX9-fLcHTxYD=DMt", "ver": 3.5},
}

def _tuya_device(name):
    d = TUYA_DEVICES[name]
    dev = tinytuya.OutletDevice(d["id"], d["ip"], d["key"], version=d["ver"])
    dev.set_socketTimeout(5)
    return dev

def tg(msg: str):
    try:
        requests.post(f"https://api.telegram.org/bot{TG_BOT}/sendMessage",
            json={"chat_id": TG_CHAT, "text": msg}, timeout=10)
    except:
        pass

def get_actual_plug_state():
    """tinytuya로 실제 20a 플러그 상태 조회 (로컬)"""
    try:
        dev = _tuya_device("charger")
        status = dev.status()
        if "dps" in status:
            return status["dps"].get("1", False)
        return None
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
        dev = _tuya_device("charger")
        if on:
            dev.turn_on()
        else:
            dev.turn_off()
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
    """mmWave 센서로 재실 확인 (로컬)"""
    try:
        dev = tinytuya.Device(
            TUYA_DEVICES["mmwave"]["id"],
            TUYA_DEVICES["mmwave"]["ip"],
            TUYA_DEVICES["mmwave"]["key"],
            version=TUYA_DEVICES["mmwave"]["ver"]
        )
        dev.set_socketTimeout(5)
        status = dev.status()
        if "dps" in status:
            # dps.1 = presence state ('peaceful'/'motion'/'none' 등)
            state = status["dps"].get("1", "none")
            return state != "none"
        return True
    except:
        return True

def should_manage():
    """배터리 관리 모드: 항상 20~80% 유지"""
    return True, ""

def heartbeat(pct, plugged):
    """Firestore에 heartbeat 전송"""
    try:
        requests.get(f"{CF_URL}?q=config&key=batteryHeartbeat&value={int(time.time())}", timeout=10)
        requests.get(f"{CF_URL}?q=config&key=batteryPercent&value={pct}", timeout=10)
        requests.get(f"{CF_URL}?q=config&key=batteryPlugOn&value={'true' if plugged else 'false'}", timeout=10)
    except:
        pass

def poll_sensors():
    """mmWave 센서 로컬 폴링 → Firestore에 기록"""
    try:
        dev = tinytuya.Device(
            TUYA_DEVICES["mmwave"]["id"],
            TUYA_DEVICES["mmwave"]["ip"],
            TUYA_DEVICES["mmwave"]["key"],
            version=TUYA_DEVICES["mmwave"]["ver"]
        )
        dev.set_socketTimeout(5)
        status = dev.status()
        if "dps" in status:
            presence = status["dps"].get("1", "none")
            distance = status["dps"].get("9", 0)
            # Firestore에 기록 (CF 엔드포인트 사용)
            requests.get(
                f"{CF_URL}?q=config&key=mmwave_presence&value={presence}",
                timeout=10)
            requests.get(
                f"{CF_URL}?q=config&key=mmwave_distance&value={distance}",
                timeout=10)
            print(f"[Sensor] mmWave: {presence}, {distance}cm")
            return presence
    except Exception as e:
        print(f"[Sensor] error: {e}")
    return None

def check():
    b = psutil.sensors_battery()
    if b is None:
        return

    pct = b.percent

    # 주기적으로 실제 플러그 상태와 동기화
    sync_plug_state()

    # 센서 폴링
    poll_sensors()

    # heartbeat 전송
    heartbeat(pct, plug_on)

    # 배터리 관리
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
