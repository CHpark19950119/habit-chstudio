"""고시 공고 크롤러 — PC에서 실행, Firestore에 결과 업로드
Task Scheduler로 매일 08:00 실행
"""
import requests, re, json

CF_URL = "https://us-central1-cheonhong-studio.cloudfunctions.net/checkDoorManual"
TG_BOT = "8253264860:AAE8mKRSNN31ubdOvk4KPghOYcOmnXg0v50"
TG_CHAT = "8724548311"
GOSI_URL = "https://gongmuwon.gosi.kr/oprut/RpaRpTestPbancLst.do"
GOSI_DETAIL = "https://gongmuwon.gosi.kr/oprut/RpaRpTestPbancDtl.do?pbancSn="

def tg(msg):
    try:
        requests.post(f"https://api.telegram.org/bot{TG_BOT}/sendMessage",
            json={"chat_id": TG_CHAT, "text": msg, "disable_web_page_preview": True}, timeout=10)
    except:
        pass

def get_last_ntt_id():
    try:
        r = requests.get(f"{CF_URL}?q=read&doc=study&field=gosiLastNttId", timeout=10)
        data = r.json()
        return data.get("value", 0) or 0
    except:
        return 0

def set_last_ntt_id(ntt_id):
    try:
        requests.get(f"{CF_URL}?q=write&doc=study&field=gosiLastNttId&value={ntt_id}", timeout=10)
    except:
        pass

def crawl():
    r = requests.get(GOSI_URL, timeout=20, headers={
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
    })
    html = r.text

    # 파싱 — <ul class="tbody"> 안의 <li style='display: none;'> 패턴
    # li[0]=ID, li[1]=제목(hidden), li[2~]=번호, 시험구분, 공고명, 게시일
    ul_blocks = re.findall(r'<ul class="tbody[^"]*">([\s\S]*?)</ul>', html)
    date_pattern = re.compile(r'(\d{4}[-./]\d{2}[-./]\d{2})')

    notices = []
    for block in ul_blocks:
        lis = re.findall(r'<li[^>]*>([\s\S]*?)</li>', block)
        if len(lis) < 4:
            continue

        # 숨겨진 li에서 ID와 제목 추출
        clean_lis = [re.sub(r'<[^>]+>', '', li).strip() for li in lis]

        ntt_id = 0
        title = ""
        exam_type = ""
        date = ""

        # 첫 번째 숨겨진 li = ID
        try:
            ntt_id = int(clean_lis[0])
        except:
            continue

        # 두 번째 숨겨진 li = 제목
        title = clean_lis[1] if len(clean_lis) > 1 else ""

        # data-title 속성에서 시험구분 추출
        type_match = re.search(r'data-title="([^"]*)"', block)
        if type_match:
            exam_type = type_match.group(1)

        # 날짜 추출
        for li in clean_lis:
            dm = date_pattern.search(li)
            if dm:
                date = dm.group(1)

        if title:
            notices.append({"nttId": ntt_id, "title": title, "date": date, "examType": exam_type})

    return notices

def main():
    last_id = get_last_ntt_id()
    print(f"[Gosi] last nttId: {last_id}")

    try:
        notices = crawl()
    except Exception as e:
        tg(f"⚠️ 고시 공고 크롤링 실패\n에러: {e}")
        print(f"[Gosi] crawl error: {e}")
        return

    if not notices:
        print("[Gosi] no notices parsed")
        return

    new_notices = [n for n in notices if n["nttId"] > last_id]

    if not new_notices:
        print(f"[Gosi] no new notices (latest: {notices[0]['nttId']})")
        return

    msg = f"📋 고시 공고 {len(new_notices)}건\n"
    for n in new_notices[:5]:
        if n["examType"]:
            msg += f"\n[{n['examType']}] "
        else:
            msg += "\n"
        msg += n["title"]
        if n["date"]:
            msg += f" ({n['date']})"
        msg += f"\n{GOSI_DETAIL}{n['nttId']}"

    if len(new_notices) > 5:
        msg += f"\n\n... 외 {len(new_notices) - 5}건"

    tg(msg)

    max_id = max(n["nttId"] for n in notices)
    set_last_ntt_id(max_id)
    print(f"[Gosi] {len(new_notices)} new, max: {max_id}")

if __name__ == "__main__":
    main()
