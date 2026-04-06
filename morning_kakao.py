"""매일 아침 다영이한테 영어 응원 메시지 카톡 전송"""
import subprocess, os, tempfile, time, random, anthropic

ANTHROPIC_API_KEY = os.environ.get("ANTHROPIC_API_KEY", "REDACTED_ANTHROPIC_KEY")

def generate_message():
    """Claude로 천홍이 인격 담은 영어 메시지 생성"""
    client = anthropic.Anthropic(api_key=ANTHROPIC_API_KEY)
    response = client.messages.create(
        model="claude-haiku-4-5-20251001",
        max_tokens=100,
        messages=[{
            "role": "user",
            "content": """Write a short good morning message in English from a Korean boyfriend (Cheonhong) to his girlfriend (Dayoung).

Rules:
- 1-3 sentences max
- Warm but not cheesy
- He's logical, direct, not overly emotional
- Sometimes witty or playful
- He's studying for government exams, she knows he's busy
- Vary the style each day - sometimes sweet, sometimes funny, sometimes thoughtful
- Don't use "babe" or "honey" - he's not that type
- End with something encouraging for her day

Just the message, nothing else."""
        }],
    )
    return response.content[0].text.strip()

def send_kakao(msg):
    """ADB로 카톡 전송"""
    cmd = f'am start -a android.intent.action.SEND -t "text/plain" --es android.intent.extra.TEXT "{msg}" -n com.kakao.talk/.activity.RecentExcludeIntentFilterActivity'
    path = os.path.join(tempfile.gettempdir(), 'morning_kakao.sh')
    with open(path, 'w', encoding='utf-8') as f:
        f.write(cmd)
    subprocess.run(['adb', 'push', path, '/data/local/tmp/morning_kakao.sh'], capture_output=True)
    subprocess.run(['adb', 'shell', 'sh /data/local/tmp/morning_kakao.sh'], capture_output=True, encoding='utf-8', errors='replace')
    time.sleep(2)
    # 다영 선택 (첫 번째 항목)
    subprocess.run(['adb', 'shell', 'input', 'tap', '540', '660'], capture_output=True)
    time.sleep(1.5)
    # 보내기
    subprocess.run(['adb', 'shell', 'input', 'tap', '540', '2100'], capture_output=True)

if __name__ == "__main__":
    msg = generate_message()
    print(f"[Morning Kakao] {msg}")
    send_kakao(msg)
    print("[Morning Kakao] sent to 다영")
