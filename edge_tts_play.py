"""Edge TTS 시나리오 재생기 — 무료 한국어 TTS
시나리오 파일의 대사를 Edge TTS로 생성 후 연결하여 하나의 MP3로 출력.
audio 태그([moans] 등)는 제거하고 대사만 추출.

사용법: python edge_tts_play.py [시나리오파일] [--output 파일명.mp3]
"""
import asyncio, os, re, sys, tempfile
import edge_tts

VOICE = "ko-KR-SunHiNeural"
RATE = "-5%"  # 약간 느리게
PITCH = "+0Hz"
OUTPUT_DIR = os.path.join(tempfile.gettempdir(), "edge_tts_out")
os.makedirs(OUTPUT_DIR, exist_ok=True)

if sys.platform == "win32":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")


def parse_scenario(path):
    """시나리오 파일에서 대사 추출. @voice: 태그, audio 태그 제거."""
    lines = []
    with open(path, encoding="utf-8") as f:
        for raw in f:
            raw = raw.strip()
            if not raw:
                continue
            # @voice: 태그 제거
            raw = re.sub(r'^@\w+:\s*', '', raw)
            # [audio tags] 제거
            raw = re.sub(r'\[.*?\]', '', raw)
            # 남은 공백 정리
            raw = re.sub(r'\s+', ' ', raw).strip()
            # ... 을 쉼표로 (자연스러운 쉼)
            raw = raw.replace('...', ',')
            if raw and len(raw) > 1:
                lines.append(raw)
    return lines


async def generate_all(lines, output_path):
    """모든 대사를 개별 MP3로 생성 후 합치기."""
    parts = []
    for i, text in enumerate(lines):
        part_path = os.path.join(OUTPUT_DIR, f"part_{i:03d}.mp3")
        print(f"  [{i+1}/{len(lines)}] {text[:40]}...")
        comm = edge_tts.Communicate(text, VOICE, rate=RATE, pitch=PITCH)
        await comm.save(part_path)
        parts.append(part_path)

    # 합치기 (바이너리 concat — MP3는 단순 이어붙이기 가능)
    print(f"\n합치는 중... → {output_path}")
    with open(output_path, "wb") as out:
        for p in parts:
            with open(p, "rb") as inp:
                out.write(inp.read())
            os.remove(p)

    size_mb = os.path.getsize(output_path) / 1024 / 1024
    print(f"완료! {size_mb:.1f}MB, {len(lines)}개 대사")
    return output_path


def main():
    scenario = sys.argv[1] if len(sys.argv) > 1 else "scenarios/gold_digger.txt"

    output = None
    if "--output" in sys.argv:
        idx = sys.argv.index("--output")
        output = sys.argv[idx + 1]

    if not output:
        base = os.path.splitext(os.path.basename(scenario))[0]
        output = os.path.join(OUTPUT_DIR, f"{base}.mp3")

    print(f"시나리오: {scenario}")
    print(f"음성: {VOICE}")
    print()

    lines = parse_scenario(scenario)
    print(f"{len(lines)}개 대사 추출\n")

    asyncio.run(generate_all(lines, output))
    print(f"\n출력: {output}")


if __name__ == "__main__":
    main()
