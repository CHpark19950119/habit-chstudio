"""기상 알람 — PL7 연결 + TTS로 깨우기"""
import subprocess, ctypes, os, tempfile, time
from openai import OpenAI

OPENAI_KEY = os.environ.get("OPENAI_API_KEY", "")
if not OPENAI_KEY:
    raise RuntimeError("OPENAI_API_KEY 환경변수가 없다. 셸에서 export 후 재실행.")
TTS_PATH = os.path.join(tempfile.gettempdir(), "wake_tts.mp3")

winmm = ctypes.windll.winmm
def mci(cmd):
    buf = ctypes.create_unicode_buffer(256)
    winmm.mciSendStringW(cmd, buf, 255, 0)
    return buf.value

def play(path):
    mci("close wake")
    mci(f'open "{path}" type mpegvideo alias wake')
    mci("play wake")
    length = 10000
    try: length = int(mci("status wake length"))
    except: pass
    elapsed = 0
    while elapsed < length + 500:
        time.sleep(0.1); elapsed += 100
        try:
            if int(mci("status wake position")) >= length: break
        except: break
    mci("close wake")

# 1. PL7 블루투스 활성화
subprocess.run(
    ["powershell", "-Command",
     "Start-Process powershell -Verb RunAs -ArgumentList '-Command', "
     "'Get-PnpDevice -FriendlyName \"LG-PL7*\" | ForEach-Object { Enable-PnpDevice -InstanceId $_.InstanceId -Confirm:$false }'"],
    capture_output=True, creationflags=0x08000000
)
time.sleep(5)  # 블루투스 연결 대기

# 2. TTS 생성
client = OpenAI(api_key=OPENAI_KEY)
messages = [
    "10시야. 일어나.",
    "오늘도 할 일 있잖아. 일어나. 세수하고 와.",
    "아직도 자? 진짜 일어나. 물 한 잔 마셔.",
]

for msg in messages:
    response = client.audio.speech.create(
        model="tts-1-hd", voice="nova", input=msg, speed=0.8
    )
    response.stream_to_file(TTS_PATH)
    play(TTS_PATH)
    time.sleep(3)
