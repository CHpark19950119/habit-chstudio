"""PICKKO 토큰 관리
토큰 만료 시 실행: python pickko_token.py renew
현재 토큰 확인: python pickko_token.py check

토큰 갱신 절차:
1. 패치된 PICKKO APK 설치 (adb install-multiple ...)
2. mitmdump --listen-port 8083 시작
3. adb reverse tcp:8083 tcp:8083
4. PICKKO 앱 열어서 로그인
5. 캡처된 토큰을 이 파일과 seats.html에 반영
6. 원본 PICKKO 재설치
"""
import json, base64, sys, os, time

TOKEN_FILE = os.path.join(os.path.dirname(__file__), ".pickko_token")

# 현재 토큰
CURRENT_TOKEN = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJhbWJObyI6Ijk3QUY5MjRDLUFBMzItNEQ0MS1CRDhELUFEQTQ0MkUzMEU0QyIsImFtYlBob25lIjoiMDEwMjQzNTgwNjciLCJhbWJOYW1lIjoi67CV7LKc7ZmNIiwiYW1iQmlydGgiOiIxOTk1LTAxLTE5IiwiYW1iR2VuZGVyIjoibWFsZSIsImlhdCI6MTc3NDU0MjczMywiZXhwIjoxNzc3MTM0NzMzfQ.gO7ohevXlACzPE5gamg8xuxOjl5t23Z-e5vqS7wak34"

def decode_jwt(token):
    payload = token.split('.')[1]
    payload += '=' * (4 - len(payload) % 4)
    return json.loads(base64.b64decode(payload))

def check():
    data = decode_jwt(CURRENT_TOKEN)
    exp = data.get("exp", 0)
    now = time.time()
    days_left = (exp - now) / 86400
    print(f"이름: {data.get('ambName', '?')}")
    print(f"만료: {time.strftime('%Y-%m-%d', time.localtime(exp))}")
    print(f"남은 일수: {days_left:.1f}일")
    if days_left < 3:
        print("⚠️ 갱신 필요!")
    else:
        print("✅ 유효")

def update_token(new_token):
    """토큰 갱신 — seats.html + check_seats.py + 이 파일 업데이트"""
    global CURRENT_TOKEN
    old = CURRENT_TOKEN

    # 1. 이 파일 업데이트
    this_file = os.path.abspath(__file__)
    with open(this_file, 'r', encoding='utf-8') as f:
        content = f.read()
    content = content.replace(old, new_token)
    with open(this_file, 'w', encoding='utf-8') as f:
        f.write(content)

    # 2. check_seats.py 업데이트
    seats_py = os.path.join(os.path.dirname(__file__), "check_seats.py")
    if os.path.exists(seats_py):
        with open(seats_py, 'r', encoding='utf-8') as f:
            content = f.read()
        content = content.replace(old, new_token)
        with open(seats_py, 'w', encoding='utf-8') as f:
            f.write(content)
        print("✅ check_seats.py 업데이트")

    # 3. seats.html 업데이트
    seats_html = os.path.join(os.path.dirname(__file__), "..", "ch-studio", "public", "seats.html")
    if not os.path.exists(seats_html):
        seats_html = "C:/dev/ch-studio/public/seats.html"
    if os.path.exists(seats_html):
        with open(seats_html, 'r', encoding='utf-8') as f:
            content = f.read()
        content = content.replace(old, new_token)
        with open(seats_html, 'w', encoding='utf-8') as f:
            f.write(content)
        print("✅ seats.html 업데이트")
        print("📌 firebase deploy --only hosting 필요")

    print(f"✅ 토큰 갱신 완료")
    data = decode_jwt(new_token)
    print(f"만료: {time.strftime('%Y-%m-%d', time.localtime(data['exp']))}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("사용법: python pickko_token.py [check|update <token>]")
        sys.exit(1)

    cmd = sys.argv[1]
    if cmd == "check":
        check()
    elif cmd == "update" and len(sys.argv) > 2:
        update_token(sys.argv[2])
    else:
        print("사용법: python pickko_token.py [check|update <token>]")
