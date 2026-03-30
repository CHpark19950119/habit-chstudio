"""
이미지/비디오 소싱 자동화 스크립트
소스: Reddit + RedGifs(이미지) + xhamster Photos

사용법:
  python image_fetcher.py --category anal --count 6
  python image_fetcher.py --sub leahgotti --count 10 --period week
  python image_fetcher.py --video --keyword "anal perfect ass" --count 3
  python image_fetcher.py --user Papisanon --count 10
  python image_fetcher.py --keyword "amateur beautiful" --count 5 --send
  python image_fetcher.py --xhamster "anal creampie" --count 5 --send
"""

import argparse
import json
import os
import sys
import urllib.request
import urllib.parse
import re
import hashlib
import html as html_mod
import tempfile
from pathlib import Path

TEMP_DIR = Path(tempfile.gettempdir())
SENT_LOG = Path(os.path.dirname(os.path.abspath(__file__))) / "sent_urls.json"

TG_TOKEN = "8253264860:AAE8mKRSNN31ubdOvk4KPghOYcOmnXg0v50"
TG_CHAT = "8724548311"
MIN_FILE_SIZE = 50 * 1024  # 50KB 미만 = 썸네일

SUBS = {
    "anal": ["assholegonewild", "anal", "buttplug", "AnalGW"],
    "asian": ["paag", "juicyasians", "AsiansGoneWild", "rice_cakes"],
    "latin": ["latinas", "latinasgw", "LatinaCuties"],
    "middle_east": ["hijabixxx"],
    "general": ["RealGirls", "gonewild", "BustyPetite"],
    "amateur": ["Amateur", "CoupleGW", "homemadexxx"],
    "body": ["fitgirls", "thickfit", "BubbleButts"],
    "masturbation": ["masturbation", "fingering", "GirlsFinishingTheJob"],
    "creampie": ["creampies", "BreedingMaterial"],
    "favorite": ["paag", "buttplug", "godpussy", "assholegonewild", "LabiaGW"],
    "celeb": ["celebnsfw", "Celebhub"],
}

HEADERS = {"User-Agent": "Claude/1.0 (contact: test@test.com)"}
BROWSER_UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"


def load_sent():
    if SENT_LOG.exists():
        try:
            return set(json.loads(SENT_LOG.read_text(encoding="utf-8")))
        except:
            return set()
    return set()


def save_sent(sent):
    SENT_LOG.parent.mkdir(parents=True, exist_ok=True)
    SENT_LOG.write_text(json.dumps(list(sent)[-5000:]), encoding="utf-8")


# ═══ Reddit ═══

def _extract_gallery_urls(post_data):
    """갤러리 포스트에서 i.redd.it 직접 이미지 URL 추출"""
    mm = post_data.get("media_metadata", {})
    if not mm:
        return []
    urls = []
    # gallery_data에 순서 정보가 있으면 사용, 없으면 전체
    ordered_ids = []
    gd = post_data.get("gallery_data", {})
    if gd and "items" in gd:
        ordered_ids = [item["media_id"] for item in gd["items"]]
    else:
        ordered_ids = list(mm.keys())

    for mid in ordered_ids:
        mdata = mm.get(mid, {})
        if mdata.get("status") != "valid":
            continue
        if mdata.get("e") == "Image":
            # i.redd.it 직접 URL (가장 깨끗)
            ext = mdata.get("m", "image/jpeg").split("/")[-1]
            if ext == "jpeg":
                ext = "jpg"
            urls.append(f"https://i.redd.it/{mid}.{ext}")
        elif mdata.get("e") == "AnimatedImage":
            # gif 등
            s = mdata.get("s", {})
            if "gif" in s:
                urls.append(html_mod.unescape(s["gif"]))
            elif "mp4" in s:
                urls.append(html_mod.unescape(s["mp4"]))
    return urls


def _extract_preview_url(post_data):
    """redgifs 등 외부 링크 포스트에서 Reddit preview 이미지 URL 추출"""
    preview = post_data.get("preview", {})
    images = preview.get("images", [])
    if not images:
        return None
    source = images[0].get("source", {})
    url = source.get("url", "")
    if url:
        return html_mod.unescape(url)
    return None


def fetch_reddit(sub, period="month", limit=50):
    """Reddit 서브레딧에서 이미지 URL 수집 (갤러리 + redgifs preview 지원)"""
    url = f"https://old.reddit.com/r/{sub}/top/.json?t={period}&limit={limit}"
    req = urllib.request.Request(url, headers=HEADERS)
    try:
        resp = urllib.request.urlopen(req, timeout=15)
        data = json.loads(resp.read())
    except Exception as e:
        print(f"  r/{sub} JSON: {e}", file=sys.stderr)
        return fetch_reddit_html(sub, period, limit)

    results = []
    for post in data.get("data", {}).get("children", []):
        d = post["data"]
        img_url = d.get("url", "")
        title = d.get("title", "")
        score = d.get("score", 0)
        author = d.get("author", "")
        base = {"title": title, "score": score, "author": author,
                "sub": sub, "source": "reddit", "type": "image"}

        # 1) 직접 이미지 링크
        if img_url.endswith((".jpg", ".jpeg", ".png", ".gif")):
            results.append({**base, "url": img_url})

        # 2) 갤러리 포스트 — media_metadata에서 개별 이미지 추출
        elif d.get("is_gallery") and d.get("media_metadata"):
            gallery_urls = _extract_gallery_urls(d)
            if gallery_urls:
                # 갤러리 첫 번째 이미지만 (전부 넣으면 너무 많음)
                results.append({**base, "url": gallery_urls[0]})

        # 3) redgifs/외부 링크 — preview 이미지 사용
        elif "redgifs.com" in img_url or "imgur.com" in img_url:
            preview_url = _extract_preview_url(d)
            if preview_url:
                results.append({**base, "url": preview_url})

    # JSON에서 결과가 0이면 HTML 파싱 fallback
    if not results:
        print(f"  r/{sub}: JSON 0 results, trying HTML fallback...")
        results = fetch_reddit_html(sub, period, limit)

    return results


def fetch_reddit_html(sub, period="month", limit=50):
    """old.reddit.com HTML 파싱 fallback (JSON이 0결과일 때 사용)"""
    sort_map = {"day": "top/?t=day", "week": "top/?t=week",
                "month": "top/?t=month", "year": "top/?t=year",
                "all": "top/?t=all", "hot": "hot/"}
    sort_path = sort_map.get(period, f"top/?t={period}")
    url = f"https://old.reddit.com/r/{sub}/{sort_path}"

    headers = {
        "User-Agent": BROWSER_UA,
        "Cookie": "over18=1",
        "Accept": "text/html,application/xhtml+xml",
        "Accept-Language": "en-US,en;q=0.9",
    }
    req = urllib.request.Request(url, headers=headers)
    try:
        resp = urllib.request.urlopen(req, timeout=20)
        html_text = resp.read().decode("utf-8", errors="replace")
    except Exception as e:
        print(f"  r/{sub} HTML fallback: {e}", file=sys.stderr)
        return []

    results = []

    # old.reddit.com의 thing div에서 data-url, data-score 추출
    for match in re.finditer(
        r'<div[^>]*class="[^"]*\s+thing\s+[^"]*"([^>]*)>', html_text
    ):
        attrs = match.group(1)
        m_url = re.search(r'data-url="([^"]+)"', attrs)
        m_score = re.search(r'data-score="([^"]+)"', attrs)
        m_author = re.search(r'data-author="([^"]+)"', attrs)
        if not m_url:
            continue

        data_url = html_mod.unescape(m_url.group(1))
        score = int(m_score.group(1)) if m_score else 0
        author = m_author.group(1) if m_author else ""
        base = {"score": score, "author": author, "sub": sub,
                "source": "reddit", "type": "image", "title": ""}

        # 직접 이미지 링크
        if re.search(r'\.(jpg|jpeg|png|gif)$', data_url, re.I):
            results.append({**base, "url": data_url})

        # i.redd.it 링크 (확장자 포함)
        elif "i.redd.it" in data_url:
            results.append({**base, "url": data_url})

    # thing div에서 못 찾으면, HTML 전체에서 i.redd.it 링크 수집
    if not results:
        i_redd_urls = re.findall(
            r'https?://i\.redd\.it/[a-zA-Z0-9_]+\.(?:jpg|jpeg|png|gif)',
            html_text,
        )
        seen = set()
        for u in i_redd_urls:
            if u not in seen:
                seen.add(u)
                results.append({
                    "url": u, "score": 0, "author": "", "sub": sub,
                    "source": "reddit", "type": "image", "title": "",
                })

    print(f"  r/{sub} HTML fallback: {len(results)} images found")
    return results[:limit]


def fetch_reddit_user(username, limit=50):
    """Reddit 유저의 전체 포스트에서 이미지 수집 (갤러리 + preview 지원)"""
    url = f"https://old.reddit.com/user/{username}/submitted/.json?sort=top&t=all&limit={limit}"
    req = urllib.request.Request(url, headers=HEADERS)
    try:
        resp = urllib.request.urlopen(req, timeout=15)
        data = json.loads(resp.read())
    except Exception as e:
        print(f"  u/{username}: {e}", file=sys.stderr)
        return []

    results = []
    for post in data.get("data", {}).get("children", []):
        d = post["data"]
        img_url = d.get("url", "")
        base = {
            "title": d.get("title", ""),
            "score": d.get("score", 0),
            "author": username,
            "sub": d.get("subreddit", ""),
            "source": "reddit",
            "type": "image",
        }

        if img_url.endswith((".jpg", ".jpeg", ".png", ".gif")):
            results.append({**base, "url": img_url})
        elif d.get("is_gallery") and d.get("media_metadata"):
            gallery_urls = _extract_gallery_urls(d)
            if gallery_urls:
                results.append({**base, "url": gallery_urls[0]})
        elif "redgifs.com" in img_url or "imgur.com" in img_url:
            preview_url = _extract_preview_url(d)
            if preview_url:
                results.append({**base, "url": preview_url})
    return results


# ═══ RedGifs (이미지 전용) ═══

def fetch_redgifs(query, count=10, images_only=False):
    """RedGifs에서 검색 (type=i로 이미지만 필터 가능)"""
    req = urllib.request.Request(
        "https://api.redgifs.com/v2/auth/temporary",
        headers={"User-Agent": "Mozilla/5.0"},
    )
    try:
        token = json.loads(urllib.request.urlopen(req, timeout=10).read())["token"]
    except Exception as e:
        print(f"  RedGifs token error: {e}", file=sys.stderr)
        return []

    type_param = "&type=i" if images_only else ""
    # tags 파라미터 사용 (search_text는 type=i에서 무시됨)
    tags = query.replace(" ", ",")
    search_url = (
        f"https://api.redgifs.com/v2/gifs/search"
        f"?tags={urllib.parse.quote(tags)}&order=top&count={count}{type_param}"
    )
    req2 = urllib.request.Request(
        search_url,
        headers={"User-Agent": "Mozilla/5.0", "Authorization": f"Bearer {token}"},
    )
    try:
        data = json.loads(urllib.request.urlopen(req2, timeout=15).read())
    except Exception as e:
        print(f"  RedGifs search error: {e}", file=sys.stderr)
        return []

    results = []
    for g in data.get("gifs", []):
        urls = g.get("urls", {})
        img_url = urls.get("hd") or urls.get("sd") or urls.get("poster", "")
        if img_url:
            results.append({
                "url": img_url,
                "score": g.get("views", 0),
                "source": "redgifs",
                "type": "image" if images_only else "video",
            })
    return results


# ═══ xhamster Photos ═══

def fetch_xhamster(query, count=10):
    """xhamster 사진 검색 (curl-cffi 필요)"""
    try:
        from curl_cffi import requests as cffi
    except ImportError:
        print("  xhamster: curl-cffi 미설치 (pip install curl-cffi)", file=sys.stderr)
        return []

    session = cffi.Session(impersonate="chrome")
    slug = query.replace(" ", "-")
    all_imgs = []

    for page in range(1, 3):  # 최대 2페이지
        url = f"https://xhamster.com/photos/search/{slug}?page={page}"
        try:
            r = session.get(url, timeout=15)
            found = re.findall(r'(https?://ic-ph[^\"\'\s]+(?:_1000|1000)[^\"\'\s]*\.(?:jpg|webp|png))', r.text)
            all_imgs.extend(found)
        except Exception as e:
            print(f"  xhamster page {page}: {e}", file=sys.stderr)
            break

    all_imgs = list(dict.fromkeys(all_imgs))  # 중복 제거
    return [
        {"url": u, "score": 0, "source": "xhamster", "type": "image"}
        for u in all_imgs[:count * 2]  # 여유분 (다운로드 실패 대비)
    ]


# ═══ 다운로드 + 텔레그램 ═══

def download_image(url, index=0):
    """이미지 다운로드. 50KB 미만 썸네일 스킵."""
    ext_match = re.search(r'\.(jpg|jpeg|png|gif|webp|mp4)', url.lower())
    ext = ext_match.group(1) if ext_match else "jpg"
    url_hash = hashlib.md5(url.encode()).hexdigest()[:12]
    filename = f"img_{url_hash}.{ext}"
    filepath = TEMP_DIR / filename

    try:
        # 소스별 Referer
        if "redgifs.com" in url:
            referer = "https://www.redgifs.com/"
        elif "xhpingcdn.com" in url or "xhamster" in url:
            referer = "https://xhamster.com/"
        elif "redd.it" in url:
            referer = "https://www.reddit.com/"
        else:
            referer = "https://www.google.com/"
        headers = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36", "Referer": referer}
        req = urllib.request.Request(url, headers=headers)
        data = urllib.request.urlopen(req, timeout=15).read()
        if len(data) < MIN_FILE_SIZE:
            print(f"  [skip] 썸네일 ({len(data)//1024}KB): {url[:60]}")
            return None
        with open(filepath, "wb") as f:
            f.write(data)
        print(f"  [v] {filename} ({len(data)//1024}KB)")
        return str(filepath)
    except Exception as e:
        print(f"  [!] 다운로드 실패: {e}")
        return None


def send_telegram(filepath, caption=""):
    """텔레그램으로 사진 전송"""
    boundary = "----FormBoundary" + hashlib.md5(filepath.encode()).hexdigest()[:16]
    filename = os.path.basename(filepath)

    with open(filepath, "rb") as f:
        file_data = f.read()

    body = (
        f'--{boundary}\r\n'
        f'Content-Disposition: form-data; name="chat_id"\r\n\r\n{TG_CHAT}\r\n'
        f'--{boundary}\r\n'
        f'Content-Disposition: form-data; name="caption"\r\n\r\n{caption}\r\n'
        f'--{boundary}\r\n'
        f'Content-Disposition: form-data; name="photo"; filename="{filename}"\r\n'
        f'Content-Type: image/jpeg\r\n\r\n'
    ).encode() + file_data + f'\r\n--{boundary}--\r\n'.encode()

    req = urllib.request.Request(
        f"https://api.telegram.org/bot{TG_TOKEN}/sendPhoto",
        data=body,
        headers={"Content-Type": f"multipart/form-data; boundary={boundary}"},
    )
    try:
        urllib.request.urlopen(req, timeout=30)
        print(f"  [T] 전송: {filename}")
        return True
    except Exception as e:
        print(f"  [!] 전송 실패: {e}")
        return False


def cleanup_file(filepath):
    """임시 파일 즉시 삭제"""
    try:
        os.unlink(filepath)
    except:
        pass


def main():
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

    parser = argparse.ArgumentParser(
        description="이미지/비디오 소싱 (Reddit + RedGifs + xhamster)",
    )
    parser.add_argument("--category", "-c", help=f"카테고리 ({', '.join(SUBS.keys())})")
    parser.add_argument("--sub", "-s", help="특정 서브레딧")
    parser.add_argument("--user", "-u", help="특정 Reddit 유저")
    parser.add_argument("--keyword", "-k", help="RedGifs 이미지 검색")
    parser.add_argument("--xhamster", "-x", help="xhamster 사진 검색")
    parser.add_argument("--video", "-v", action="store_true", help="비디오 모드 (RedGifs)")
    parser.add_argument("--count", "-n", type=int, default=6, help="가져올 개수 (기본 6)")
    parser.add_argument("--period", "-p", default="month", help="기간 (day/week/month/year/all)")
    parser.add_argument("--send", action="store_true", help="텔레그램 전송")
    parser.add_argument("--download", "-d", action="store_true", help="다운로드만")
    parser.add_argument("--all", "-a", help="키워드로 모든 소스 동시 검색")
    parser.add_argument("--no-dedup", action="store_true", help="중복 체크 비활성화")
    args = parser.parse_args()

    sent = set() if args.no_dedup else load_sent()
    results = []

    # --all: 모든 소스 동시 검색
    if args.all:
        keyword = args.all
        print(f"[전체 검색] '{keyword}' — Reddit + RedGifs + xhamster")
        # Reddit: 관련 서브에서 키워드 필터
        for sub in ["gonewild", "RealGirls", "Amateur", "AsiansGoneWild", "assholegonewild"]:
            for r in fetch_reddit(sub, "all", 50):
                if any(w in r["title"].lower() for w in keyword.lower().split()):
                    results.append(r)
        # RedGifs 이미지
        print(f"  RedGifs 이미지 검색...")
        results.extend(fetch_redgifs(keyword, args.count * 2, images_only=True))
        # xhamster
        print(f"  xhamster 사진 검색...")
        results.extend(fetch_xhamster(keyword, args.count * 2))

    elif args.video:
        query = args.keyword or "trending"
        print(f"RedGifs 비디오: {query}")
        results = fetch_redgifs(query, args.count)

    elif args.keyword:
        print(f"RedGifs 이미지: {args.keyword}")
        results = fetch_redgifs(args.keyword, args.count * 2, images_only=True)

    elif args.xhamster:
        print(f"xhamster 사진: {args.xhamster}")
        results = fetch_xhamster(args.xhamster, args.count * 2)

    elif args.user:
        print(f"u/{args.user} 포스트 수집")
        results = fetch_reddit_user(args.user, limit=args.count * 2)

    elif args.sub:
        print(f"r/{args.sub} 수집")
        results = fetch_reddit(args.sub, args.period, limit=args.count * 2)

    elif args.category:
        subs = SUBS.get(args.category, [])
        if not subs:
            print(f"알 수 없는 카테고리: {args.category}")
            print(f"사용 가능: {', '.join(SUBS.keys())}")
            return
        print(f"카테고리 '{args.category}' — {len(subs)}개 서브레딧")
        for sub in subs:
            results.extend(fetch_reddit(sub, args.period, limit=30))
    else:
        parser.print_help()
        return

    # 중복 제거
    if not args.no_dedup:
        results = [r for r in results if r["url"] not in sent]

    # 점수순 정렬
    results.sort(key=lambda x: x.get("score", 0), reverse=True)
    results = results[:args.count]

    print(f"\n총 {len(results)}개 결과:")
    sent_count = 0
    for i, r in enumerate(results):
        url = r["url"]
        src = r.get("source", "?")
        if r["type"] == "video":
            print(f"  [{i+1}] [{src}] {r.get('score', 0)} views — {url[:80]}")
        else:
            title = r.get("title", "")[:40]
            print(f"  [{i+1}] [{src}] [{r.get('score', 0)}] {title}")
            print(f"       {url[:80]}")

        if args.download or args.send:
            path = download_image(url, i)
            if path:
                if args.send:
                    caption = f"{src} ({i+1}/{len(results)})"
                    if send_telegram(path, caption):
                        sent_count += 1
                    cleanup_file(path)
                # download only: 파일 유지
            sent.add(url)

    if args.send:
        print(f"\n텔레그램 전송: {sent_count}/{len(results)}")

    if not args.no_dedup:
        save_sent(sent)
    print(f"완료. 중복 추적: {len(sent)}개 URL 기록됨.")


if __name__ == "__main__":
    main()
