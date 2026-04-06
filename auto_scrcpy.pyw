"""
USB 연결 감지 -> scrcpy 자동 실행
ADB 폴링 (30초) — WMI 의존성 제거, Python 3.14 호환
"""
import subprocess
import time
import sys
import os

SCRCPY = r"C:\Users\mla95\OneDrive\바탕 화면\scrcpy-win64-v3.3.4\scrcpy.exe"
POLL_INTERVAL = 30  # seconds
CREATE_NO_WINDOW = 0x08000000

was_connected = False


def is_device_connected():
    try:
        result = subprocess.run(
            ["adb", "devices"],
            capture_output=True, text=True, timeout=5,
            creationflags=CREATE_NO_WINDOW
        )
        for line in result.stdout.strip().split("\n")[1:]:
            if "\tdevice" in line:
                return True
    except Exception:
        pass
    return False


def is_scrcpy_running():
    try:
        result = subprocess.run(
            ["tasklist", "/FI", "IMAGENAME eq scrcpy.exe"],
            capture_output=True, text=True, timeout=5,
            creationflags=CREATE_NO_WINDOW
        )
        return "scrcpy.exe" in result.stdout
    except Exception:
        return False


def launch_scrcpy():
    if is_scrcpy_running():
        return
    subprocess.Popen(
        [SCRCPY, "--turn-screen-off", "--stay-awake"],
        cwd=os.path.dirname(SCRCPY),
        creationflags=CREATE_NO_WINDOW
    )


if __name__ == "__main__":
    while True:
        try:
            connected = is_device_connected()
            if connected and not was_connected:
                time.sleep(3)  # adb 안정화 대기
                launch_scrcpy()
            was_connected = connected
        except Exception:
            pass
        time.sleep(POLL_INTERVAL)
