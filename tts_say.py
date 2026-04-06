"""직접 TTS 재생 — edge_tts + PowerShell MediaPlayer (창 안 뜸)"""
import asyncio, tempfile, os, sys, subprocess
import edge_tts

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
sys.stderr.reconfigure(encoding="utf-8", errors="replace")

VOICE = "ko-KR-SunHiNeural"
RATE = "-5%"
TTS_DIR = os.path.join(tempfile.gettempdir(), "tts_say")
os.makedirs(TTS_DIR, exist_ok=True)
_c = 0

async def speak(text):
    global _c
    _c += 1
    mp3 = os.path.join(TTS_DIR, f"say_{_c:04d}.mp3")
    comm = edge_tts.Communicate(text, VOICE, rate=RATE)
    await comm.save(mp3)

    mp3_uri = mp3.replace("\\", "/")
    ps_script = f"""
Add-Type -AssemblyName PresentationCore
$p = New-Object System.Windows.Media.MediaPlayer
$p.Open([Uri]::new("{mp3_uri}"))
$p.Play()
while ($p.NaturalDuration.HasTimeSpan -eq $false) {{ Start-Sleep -Milliseconds 100 }}
$dur = $p.NaturalDuration.TimeSpan.TotalMilliseconds
Start-Sleep -Milliseconds ($dur + 200)
$p.Close()
"""
    subprocess.run(
        ["powershell", "-NoProfile", "-Command", ps_script],
        capture_output=True, timeout=30
    )
    print(f"[TTS] {text}")

if __name__ == "__main__":
    text = " ".join(sys.argv[1:]) if len(sys.argv) > 1 else "테스트"
    asyncio.run(speak(text))
