"""게임 같이 보기 — 화면 캡처 + TTS 코멘트"""
import asyncio, tempfile, os, sys, time, random

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
sys.stderr.reconfigure(encoding="utf-8", errors="replace")

import edge_tts

VOICE = "ko-KR-SunHiNeural"
RATE = "-5%"
TTS_DIR = os.path.join(tempfile.gettempdir(), "game_buddy_tts")
os.makedirs(TTS_DIR, exist_ok=True)

_counter = 0

async def speak(text):
    global _counter
    _counter += 1
    out = os.path.join(TTS_DIR, f"buddy_{_counter:04d}.mp3")
    try:
        comm = edge_tts.Communicate(text, VOICE, rate=RATE)
        await comm.save(out)
        os.system(f'start "" "{out}"')
        print(f"[TTS] {text}")
    except Exception as e:
        print(f"[TTS ERROR] {e}")

if __name__ == "__main__":
    text = sys.argv[1] if len(sys.argv) > 1 else "테스트"
    asyncio.run(speak(text))
