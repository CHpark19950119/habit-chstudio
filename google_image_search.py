"""Google 이미지 검색 스크래퍼 + 텔레그램 전송
DrissionPage (headed Chrome, 별도 프로필) — Google bot detection 우회

사용법:
  python google_image_search.py "query" --count 5 --send
  python google_image_search.py "query" -n 10 --send --scroll 3
  python google_image_search.py "query" --min-width 800 --min-height 600
"""
import argparse
import hashlib
import json
import os
import re
import ssl
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

sys.stdout.reconfigure(encoding='utf-8', errors='replace')

TG_TOKEN = "8253264860:AAE8mKRSNN31ubdOvk4KPghOYcOmnXg0v50"
TG_CHAT = "8724548311"
SENT_URLS_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "sent_urls.json")
CHROME_PROFILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".chrome_scraper")
MIN_FILE_SIZE = 50 * 1024  # 50KB minimum for downloads

_ssl_ctx = ssl.create_default_context()
_ssl_ctx.check_hostname = False
_ssl_ctx.verify_mode = ssl.CERT_NONE

UA = (
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
    'AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/146.0.0.0 Safari/537.36'
)


def _make_browser():
    """DrissionPage Chromium with fresh profile (Google SafeSearch 쿠키 방지)."""
    import shutil
    from DrissionPage import Chromium, ChromiumOptions
    # ★ 매번 프로필 초기화 — Google이 반복 NSFW 검색 시 SafeSearch 강제 적용하므로
    if os.path.exists(CHROME_PROFILE):
        shutil.rmtree(CHROME_PROFILE, ignore_errors=True)
    co = ChromiumOptions()
    co.set_user_data_path(CHROME_PROFILE)
    co.set_argument('--disable-blink-features=AutomationControlled')
    co.set_argument('--no-first-run')
    co.set_argument('--no-default-browser-check')
    co.auto_port()
    return Chromium(co)


def google_image_search(query, scroll_count=2, min_width=200, min_height=200, safe_off=True):
    """Google Image Search → list of (url, width, height).

    Args:
        query: search query string
        scroll_count: how many times to scroll down for more results (each scroll ~20-40 more)
        min_width: minimum image width filter
        min_height: minimum image height filter
        safe_off: SafeSearch off (default True)

    Returns:
        list of (url, width, height) tuples, deduplicated
    """
    safe = 'off' if safe_off else 'active'
    encoded = urllib.parse.quote(query)
    url = f'https://www.google.com/search?q={encoded}&tbm=isch&safe={safe}'

    print(f'[검색] Google Images: "{query}" (safe={safe})')

    browser = _make_browser()
    try:
        page = browser.latest_tab
        page.get(url)
        page.wait(3)

        current_url = page.url
        if '/sorry/' in current_url or 'consent' in current_url:
            print('[차단] Google captcha/consent 감지')
            # Try to handle consent page
            try:
                reject_btn = page.ele('text:모두 거부') or page.ele('text:Reject all')
                if reject_btn:
                    reject_btn.click()
                    page.wait(2)
            except Exception:
                pass
            if '/sorry/' in page.url:
                print('[실패] captcha 우회 불가')
                return []

        # Scroll to load more results
        for i in range(scroll_count):
            page.scroll.to_bottom()
            page.wait(1.5)
            # Click "더보기" / "Show more results" if visible
            try:
                more_btn = page.ele('text:결과 더보기') or page.ele('text:Show more results')
                if more_btn:
                    more_btn.click()
                    page.wait(2)
            except Exception:
                pass

        source = page.html
        print(f'[페이지] {len(source):,} chars')

    finally:
        browser.quit()

    return _extract_urls(source, min_width, min_height)


def _extract_urls(source, min_width=200, min_height=200):
    """Extract original image URLs from Google Image Search page source.

    Google embeds image data as ["URL", width, height] arrays in script tags.
    """
    pattern = re.compile(r'\["(https?://[^"]+)"[,\s]*(\d{3,})[,\s]*(\d{3,})\]')
    matches = pattern.findall(source)

    seen = set()
    results = []
    skip_domains = {'google.com', 'gstatic.com', 'googleapis.com', 'google.co.kr',
                    'googleusercontent.com', 'ggpht.com'}

    for url, w, h in matches:
        # Decode unicode escapes
        url = (url.replace(r'\u003d', '=')
                  .replace(r'\u0026', '&')
                  .replace(r'\u003e', '>')
                  .replace(r'\u003c', '<'))

        if url in seen:
            continue

        # Skip Google-owned domains
        domain = urllib.parse.urlparse(url).netloc.lower()
        if any(d in domain for d in skip_domains):
            continue

        w_int, h_int = int(w), int(h)
        if w_int < min_width or h_int < min_height:
            continue

        seen.add(url)
        results.append((url, w_int, h_int))

    print(f'[추출] {len(results)}개 이미지 URL')
    return results


# --- Telegram / Download (reused from Bing version) ---

def load_sent_urls():
    if os.path.exists(SENT_URLS_FILE):
        try:
            with open(SENT_URLS_FILE, 'r', encoding='utf-8') as f:
                data = json.load(f)
                if isinstance(data, list):
                    return set(data)
        except Exception:
            pass
    return set()


def save_sent_urls(urls_set):
    with open(SENT_URLS_FILE, 'w', encoding='utf-8') as f:
        json.dump(list(urls_set), f, ensure_ascii=False)


def download_image(url, index):
    """Download image. Returns path or None if < 50KB."""
    try:
        req = urllib.request.Request(url, headers={
            'User-Agent': UA,
            'Referer': urllib.parse.urlparse(url).scheme + '://' + urllib.parse.urlparse(url).netloc + '/',
            'Accept': 'image/webp,image/apng,image/*,*/*;q=0.8',
        })
        resp = urllib.request.urlopen(req, timeout=15, context=_ssl_ctx)
        data = resp.read()

        if len(data) < MIN_FILE_SIZE:
            return None

        ct = resp.headers.get('Content-Type', '')
        if 'png' in ct:
            ext = '.png'
        elif 'gif' in ct:
            ext = '.gif'
        elif 'webp' in ct:
            ext = '.webp'
        else:
            ext = '.jpg'

        path = os.path.join(tempfile.gettempdir(), f'gimg_{index}{ext}')
        with open(path, 'wb') as f:
            f.write(data)
        return path
    except Exception as e:
        print(f'  [다운로드 실패] {url[:60]}... : {e}')
        return None


def send_telegram_photo(filepath, caption=""):
    boundary = "----Bound" + hashlib.md5(filepath.encode()).hexdigest()[:8]
    with open(filepath, "rb") as f:
        file_data = f.read()

    filename = os.path.basename(filepath)
    ct = {'png': 'image/png', 'gif': 'image/gif', 'webp': 'image/webp'}.get(
        filename.rsplit('.', 1)[-1], 'image/jpeg')

    body = (
        f'--{boundary}\r\n'
        f'Content-Disposition: form-data; name="chat_id"\r\n\r\n{TG_CHAT}\r\n'
        f'--{boundary}\r\n'
        f'Content-Disposition: form-data; name="caption"\r\n\r\n{caption}\r\n'
        f'--{boundary}\r\n'
        f'Content-Disposition: form-data; name="photo"; filename="{filename}"\r\n'
        f'Content-Type: {ct}\r\n\r\n'
    ).encode('utf-8') + file_data + f'\r\n--{boundary}--\r\n'.encode('utf-8')

    req = urllib.request.Request(
        f"https://api.telegram.org/bot{TG_TOKEN}/sendPhoto",
        data=body,
        headers={"Content-Type": f"multipart/form-data; boundary={boundary}"},
    )
    try:
        urllib.request.urlopen(req, timeout=30)
        return True
    except Exception as e:
        print(f'  [텔레그램 전송 실패] {e}')
        if len(file_data) > 5 * 1024 * 1024:
            return _send_telegram_document(filepath, caption)
        return False


def _send_telegram_document(filepath, caption=""):
    boundary = "----Bound" + hashlib.md5(filepath.encode()).hexdigest()[:8]
    with open(filepath, "rb") as f:
        file_data = f.read()
    filename = os.path.basename(filepath)
    body = (
        f'--{boundary}\r\n'
        f'Content-Disposition: form-data; name="chat_id"\r\n\r\n{TG_CHAT}\r\n'
        f'--{boundary}\r\n'
        f'Content-Disposition: form-data; name="caption"\r\n\r\n{caption}\r\n'
        f'--{boundary}\r\n'
        f'Content-Disposition: form-data; name="document"; filename="{filename}"\r\n'
        f'Content-Type: application/octet-stream\r\n\r\n'
    ).encode('utf-8') + file_data + f'\r\n--{boundary}--\r\n'.encode('utf-8')
    req = urllib.request.Request(
        f"https://api.telegram.org/bot{TG_TOKEN}/sendDocument",
        data=body,
        headers={"Content-Type": f"multipart/form-data; boundary={boundary}"},
    )
    try:
        urllib.request.urlopen(req, timeout=60)
        return True
    except Exception as e:
        print(f'  [document 전송 실패] {e}')
        return False


def main():
    parser = argparse.ArgumentParser(description='Google 이미지 검색 스크래퍼 (SafeSearch off)')
    parser.add_argument('query', help='검색어')
    parser.add_argument('--count', '-n', type=int, default=5, help='다운로드/전송할 이미지 수 (기본: 5)')
    parser.add_argument('--send', action='store_true', help='텔레그램으로 전송')
    parser.add_argument('--scroll', type=int, default=2, help='스크롤 횟수 (기본: 2, 더 많은 결과)')
    parser.add_argument('--min-width', type=int, default=400, help='최소 너비 (기본: 400)')
    parser.add_argument('--min-height', type=int, default=400, help='최소 높이 (기본: 400)')
    parser.add_argument('--no-dedup', action='store_true', help='중복 필터 끄기')
    parser.add_argument('--save-dir', type=str, default=None, help='이미지 저장 디렉토리')
    parser.add_argument('--safe', action='store_true', help='SafeSearch 켜기')
    args = parser.parse_args()

    sent_urls = load_sent_urls() if not args.no_dedup else set()
    print(f'[중복 필터] {len(sent_urls)}개 기존 URL')

    results = google_image_search(
        args.query,
        scroll_count=args.scroll,
        min_width=args.min_width,
        min_height=args.min_height,
        safe_off=not args.safe,
    )

    if not results:
        print('[결과 없음]')
        return

    all_urls = [url for url, w, h in results]

    # Dedup
    new_urls = [u for u in all_urls if u not in sent_urls]
    skipped = len(all_urls) - len(new_urls)
    if skipped > 0:
        print(f'[중복 제외] {skipped}개')

    target_urls = new_urls[:args.count]
    print(f'[대상] {len(target_urls)}개 다운로드')

    downloaded = []
    for i, url in enumerate(target_urls):
        print(f'  [{i + 1}/{len(target_urls)}] {url[:80]}...')
        path = download_image(url, i)
        if path:
            size_kb = os.path.getsize(path) / 1024
            print(f'    -> {size_kb:.0f}KB')
            downloaded.append((url, path))
        else:
            print(f'    -> 건너뜀')
        time.sleep(0.3)

    print(f'\n[다운로드] {len(downloaded)}/{len(target_urls)}개')

    if not downloaded:
        print('[완료] 다운로드된 이미지 없음')
        return

    if args.save_dir:
        os.makedirs(args.save_dir, exist_ok=True)
        for url, path in downloaded:
            ext = os.path.splitext(path)[1]
            h = hashlib.md5(url.encode()).hexdigest()[:10]
            dest = os.path.join(args.save_dir, f'{h}{ext}')
            with open(path, 'rb') as src, open(dest, 'wb') as dst:
                dst.write(src.read())
            print(f'  저장: {dest}')

    if args.send:
        sent_count = 0
        newly_sent = set()
        for i, (url, path) in enumerate(downloaded):
            caption = f'Google: {args.query} ({i + 1}/{len(downloaded)})'
            if send_telegram_photo(path, caption):
                sent_count += 1
                newly_sent.add(url)
                print(f'  전송 [{sent_count}] 완료')
            time.sleep(1)

        if newly_sent and not args.no_dedup:
            sent_urls.update(newly_sent)
            save_sent_urls(sent_urls)
            print(f'[저장] sent_urls.json ({len(newly_sent)}개 추가)')

        print(f'\n[전송 완료] {sent_count}/{len(downloaded)}개')
    else:
        print('\n[완료] --send 없이 다운로드만')
        for url, path in downloaded:
            print(f'  {path}')

    if not args.save_dir:
        for url, path in downloaded:
            try:
                os.remove(path)
            except OSError:
                pass


if __name__ == '__main__':
    main()
