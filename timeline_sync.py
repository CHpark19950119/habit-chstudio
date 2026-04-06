"""
timeline_sync.py — Google Maps Timeline 동기화 & 분석

Usage:
    python timeline_sync.py sync              # ADB pull + diff
    python timeline_sync.py today             # 오늘 요약
    python timeline_sync.py 2026-03-29        # 특정 날짜 요약
    python timeline_sync.py upload            # 오늘 Firestore 업로드
    python timeline_sync.py upload 2026-03-29 # 특정 날짜 업로드
    python timeline_sync.py export            # 폰에서 내보내기 + pull + 파싱
"""

import io
import json
import os
import sys
import subprocess
import hashlib
from datetime import datetime, timedelta, timezone
from math import radians, sin, cos, sqrt, atan2
from urllib.parse import urlencode

# Fix Windows console encoding for Korean/Unicode output
if sys.platform == "win32":
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
    sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding="utf-8", errors="replace")

try:
    import requests
except ImportError:
    requests = None

# ── Config ──────────────────────────────────────────────────────────────
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
TIMELINE_FILE = os.path.join(BASE_DIR, "timeline_data.json")
BASELINE_FILE = os.path.join(BASE_DIR, ".timeline_baseline.json")
ADB_HOST = "100.104.65.71:5555"
ADB_CMD = f"adb -s {ADB_HOST}"
# SD card paths to try (Korean original name, then English renamed)
PHONE_PATHS = [
    "/storage/4A21-0000/Timeline/타임라인.json",
    "/storage/4A21-0000/Timeline/Timeline.json",
    "/storage/4A21-0000/타임라인/타임라인.json",
]
CF_BASE = "https://us-central1-cheonhong-studio.cloudfunctions.net/checkDoorManual"
KST = timezone(timedelta(hours=9))

# Home: ~37.3137, ~126.926, 200m radius
HOME_LAT = 37.3137
HOME_LNG = 126.926
HOME_RADIUS_M = 200

# Activity type labels (Korean)
ACTIVITY_LABELS = {
    "WALKING": "도보",
    "IN_BUS": "버스",
    "IN_SUBWAY": "지하철",
    "IN_PASSENGER_VEHICLE": "차량",
    "IN_VEHICLE": "차량",
    "CYCLING": "자전거",
    "RUNNING": "달리기",
    "FLYING": "비행",
}

SEMANTIC_LABELS = {
    "HOME": "집",
    "INFERRED_HOME": "집",
    "INFERRED_WORK": "직장",
    "UNKNOWN": "",
}


# ── Utilities ───────────────────────────────────────────────────────────

def parse_latlng(s: str) -> tuple:
    """Parse '37.3138998°, 126.9256182°' -> (37.3138998, 126.9256182)"""
    parts = s.replace("\u00b0", "").split(",")
    return float(parts[0].strip()), float(parts[1].strip())


def haversine_m(lat1, lon1, lat2, lon2) -> float:
    """Distance in meters between two lat/lng points."""
    R = 6371000
    dlat = radians(lat2 - lat1)
    dlon = radians(lon2 - lon1)
    a = sin(dlat / 2) ** 2 + cos(radians(lat1)) * cos(radians(lat2)) * sin(dlon / 2) ** 2
    return R * 2 * atan2(sqrt(a), sqrt(1 - a))


def is_home(lat: float, lng: float) -> bool:
    return haversine_m(lat, lng, HOME_LAT, HOME_LNG) <= HOME_RADIUS_M


def parse_time(s: str) -> datetime:
    """Parse ISO time string like '2026-03-29T14:22:00.000+09:00'."""
    # Python 3.7+ handles +09:00 with fromisoformat in 3.11+
    # For broader compat, handle manually
    s = s.strip()
    # Replace the timezone +09:00 style
    if s.endswith("Z"):
        s = s[:-1] + "+00:00"
    try:
        return datetime.fromisoformat(s)
    except ValueError:
        # Fallback: strip millis if needed
        if "." in s:
            base, rest = s.split(".", 1)
            # rest might be '000+09:00'
            idx = rest.find("+")
            if idx == -1:
                idx = rest.find("-")
            if idx >= 0:
                tz_part = rest[idx:]
                return datetime.fromisoformat(base + tz_part)
        raise


def fmt_time(dt: datetime) -> str:
    """Format as HH:MM."""
    return dt.strftime("%H:%M")


def fmt_duration(start: datetime, end: datetime) -> str:
    """Format duration as human-readable string."""
    total = int((end - start).total_seconds())
    if total < 0:
        total = 0
    h, m = divmod(total // 60, 60)
    if h > 0:
        return f"{h}시간 {m}분" if m > 0 else f"{h}시간"
    return f"{m}분"


def fmt_distance(meters: float) -> str:
    if meters >= 1000:
        return f"{meters / 1000:.1f}km"
    return f"{meters:.0f}m"


def get_effective_date(dt: datetime) -> str:
    """4AM boundary: if hour < 4, belongs to previous date."""
    if dt.hour < 4:
        dt = dt - timedelta(days=1)
    return dt.strftime("%Y-%m-%d")


def today_str() -> str:
    """Get today's effective date string."""
    now = datetime.now(KST)
    return get_effective_date(now)


def load_timeline() -> dict:
    """Load timeline_data.json."""
    with open(TIMELINE_FILE, "r", encoding="utf-8") as f:
        return json.load(f)


def run_adb(args: str, timeout: int = 30) -> tuple:
    """Run ADB command, return (returncode, stdout, stderr)."""
    cmd = f"{ADB_CMD} {args}"
    env = os.environ.copy()
    env["MSYS_NO_PATHCONV"] = "1"
    try:
        r = subprocess.run(
            cmd, shell=True, capture_output=True, text=True,
            timeout=timeout, env=env,
        )
        return r.returncode, r.stdout, r.stderr
    except subprocess.TimeoutExpired:
        return -1, "", "timeout"


# ── Commands ────────────────────────────────────────────────────────────

def cmd_sync():
    """Pull timeline from phone, diff with baseline, save new baseline."""
    print("=== Timeline Sync ===\n")

    # 1. Ensure ADB connected
    print("[1] ADB 연결 확인...")
    rc, out, err = run_adb("devices", timeout=10)
    if ADB_HOST not in out:
        print(f"    ADB 연결 시도: {ADB_HOST}")
        rc, out, err = run_adb(f"connect {ADB_HOST}", timeout=15)
        if rc != 0 or "connected" not in out.lower():
            print(f"    ✗ ADB 연결 실패: {err.strip()}")
            return False
    print(f"    ✓ ADB 연결됨")

    # 2. Pull file
    print("[2] 타임라인 파일 다운로드...")
    pulled = False
    for phone_path in PHONE_PATHS:
        print(f"    시도: {phone_path}")
        rc, out, err = run_adb(f'pull "{phone_path}" "{TIMELINE_FILE}"', timeout=120)
        if rc == 0 and "error" not in err.lower():
            pulled = True
            # Parse file size from adb output
            print(f"    ✓ 다운로드 완료")
            break
        else:
            print(f"    ✗ {err.strip()[:80]}")

    if not pulled:
        print("    ✗ 모든 경로 실패. 파일명/경로 확인 필요.")
        return False

    # 3. Check file size
    size = os.path.getsize(TIMELINE_FILE)
    print(f"    파일 크기: {size / 1024 / 1024:.1f}MB")

    # 4. Diff with baseline
    print("[3] 변경 사항 비교...")
    data = load_timeline()
    segments = data.get("semanticSegments", [])
    new_count = len(segments)

    if os.path.exists(BASELINE_FILE):
        with open(BASELINE_FILE, "r", encoding="utf-8") as f:
            baseline = json.load(f)
        old_count = baseline.get("segment_count", 0)
        old_hash = baseline.get("last_hash", "")

        # Hash current data for quick comparison
        current_hash = hashlib.md5(
            json.dumps(segments[-100:], sort_keys=True).encode()
        ).hexdigest()

        if current_hash == old_hash and new_count == old_count:
            print(f"    변경 없음 (세그먼트 {new_count}개)")
        else:
            diff = new_count - old_count
            print(f"    세그먼트: {old_count} → {new_count} ({'+' if diff >= 0 else ''}{diff})")

            # Find new segments (after last baseline timestamp)
            old_last_time = baseline.get("last_time", "")
            if old_last_time:
                new_segs = [s for s in segments if s.get("startTime", "") > old_last_time]
                if new_segs:
                    print(f"    새 세그먼트: {len(new_segs)}개")
                    # Show date range of new segments
                    first_t = new_segs[0]["startTime"][:10]
                    last_t = new_segs[-1]["startTime"][:10]
                    print(f"    범위: {first_t} ~ {last_t}")
    else:
        print(f"    첫 동기화. 세그먼트 {new_count}개 로드됨.")

    # 5. Save new baseline
    last_time = segments[-1]["startTime"] if segments else ""
    current_hash = hashlib.md5(
        json.dumps(segments[-100:], sort_keys=True).encode()
    ).hexdigest()
    baseline_data = {
        "segment_count": new_count,
        "last_hash": current_hash,
        "last_time": last_time,
        "synced_at": datetime.now(KST).isoformat(),
    }
    with open(BASELINE_FILE, "w", encoding="utf-8") as f:
        json.dump(baseline_data, f, indent=2, ensure_ascii=False)
    print(f"    ✓ 베이스라인 저장됨")

    print(f"\n완료. `python timeline_sync.py today` 로 오늘 요약 확인.")
    return True


def get_day_segments(data: dict, target_date: str) -> list:
    """
    Extract segments for a given date (YYYY-MM-DD), respecting 4AM boundary.
    A segment belongs to target_date if its start time falls in
    [target_date 04:00, target_date+1 04:00).
    """
    # Parse target date
    d = datetime.strptime(target_date, "%Y-%m-%d")
    day_start = datetime(d.year, d.month, d.day, 4, 0, 0, tzinfo=KST)
    day_end = day_start + timedelta(days=1)

    results = []
    for seg in data.get("semanticSegments", []):
        # Skip timelinePath segments (raw GPS noise)
        if "timelinePath" in seg:
            continue

        start = parse_time(seg["startTime"])
        end = parse_time(seg["endTime"])

        # Segment overlaps with our day window
        if start < day_end and end > day_start:
            results.append(seg)

    # Sort by start time
    results.sort(key=lambda s: s["startTime"])
    return results


def format_summary(segments: list, target_date: str) -> dict:
    """
    Build a structured summary from segments.
    Returns dict with movements, stays, outing/return times, stats.
    """
    entries = []
    total_distance = 0
    outing_time = None
    return_time = None
    locations = []

    # Day window for clipping display times
    d = datetime.strptime(target_date, "%Y-%m-%d")
    day_start = datetime(d.year, d.month, d.day, 4, 0, 0, tzinfo=KST)
    day_end = day_start + timedelta(days=1)

    # Track home visits to detect outing/return
    was_home = True  # assume start of day at home

    for seg in segments:
        start = parse_time(seg["startTime"])
        end = parse_time(seg["endTime"])

        # Clip to day window for display (actual data preserved in start/end fields)
        disp_start = max(start, day_start)
        disp_end = min(end, day_end)
        duration = fmt_duration(disp_start, disp_end)

        if "visit" in seg:
            visit = seg["visit"]
            tc = visit.get("topCandidate", {})
            sem_type = tc.get("semanticType", "UNKNOWN")
            place_loc = tc.get("placeLocation", {}).get("latLng", "")

            lat, lng = 0, 0
            if place_loc:
                lat, lng = parse_latlng(place_loc)

            at_home = is_home(lat, lng) or sem_type in ("HOME", "INFERRED_HOME")

            label = SEMANTIC_LABELS.get(sem_type, "")
            if not label and at_home:
                label = "집"

            if at_home:
                # Returning home
                if not was_home:
                    return_time = start
                was_home = True
            else:
                # At a non-home location
                was_home = False
                loc_str = f"{lat:.4f},{lng:.4f}"
                if label:
                    loc_str = f"{label} ({lat:.4f},{lng:.4f})"
                if loc_str not in locations:
                    locations.append(loc_str)

            place_label = label if label else f"({lat:.4f},{lng:.4f})"
            time_prefix = "~" if start < day_start else ""
            time_suffix = "~" if end > day_end else ""
            entry = {
                "type": "체류",
                "time": f"{time_prefix}{fmt_time(disp_start)}-{fmt_time(disp_end)}{time_suffix}",
                "label": f"체류 {place_label}",
                "duration": duration,
                "detail": place_label,
                "start": start.isoformat(),
                "end": end.isoformat(),
            }
            entries.append(entry)

        elif "activity" in seg:
            act = seg["activity"]
            tc = act.get("topCandidate", {})
            act_type = tc.get("type", "UNKNOWN")
            dist = act.get("distanceMeters", 0)
            total_distance += dist

            label = ACTIVITY_LABELS.get(act_type, act_type)

            # Detect first departure from home
            if was_home and outing_time is None:
                start_loc = act.get("start", {}).get("latLng", "")
                if start_loc:
                    slat, slng = parse_latlng(start_loc)
                    if is_home(slat, slng):
                        outing_time = start

            entry = {
                "type": "이동",
                "time": f"{fmt_time(disp_start)}-{fmt_time(disp_end)}",
                "label": f"{label} {fmt_distance(dist)}",
                "duration": duration,
                "activityType": act_type,
                "distance": round(dist),
                "start": start.isoformat(),
                "end": end.isoformat(),
            }
            entries.append(entry)

    return {
        "date": target_date,
        "entries": entries,
        "outingTime": outing_time.isoformat() if outing_time else None,
        "returnHome": return_time.isoformat() if return_time else None,
        "totalDistance": round(total_distance),
        "locationsVisited": locations,
    }


def print_summary(summary: dict):
    """Print formatted summary to terminal."""
    date = summary["date"]
    entries = summary["entries"]
    total_dist = summary["totalDistance"]

    print(f"\n{'='*50}")
    print(f"  [{date}] 타임라인")
    print(f"{'='*50}\n")

    if not entries:
        print("  (데이터 없음)\n")
        return

    for e in entries:
        time_str = e["time"]
        label = e["label"]
        duration = e["duration"]
        marker = ">>" if e["type"] == "이동" else "**"
        print(f"  {marker} {time_str}  {label}  ({duration})")

    print(f"\n{'─'*50}")
    print(f"  총 이동 거리: {fmt_distance(total_dist)}")

    if summary["outingTime"]:
        ot = parse_time(summary["outingTime"])
        print(f"  외출 시간: {fmt_time(ot)}")
    if summary["returnHome"]:
        rt = parse_time(summary["returnHome"])
        print(f"  귀가 시간: {fmt_time(rt)}")

    if summary["locationsVisited"]:
        print(f"  방문 장소: {len(summary['locationsVisited'])}곳")
        for loc in summary["locationsVisited"]:
            print(f"    • {loc}")

    print()


def cmd_day(target_date: str):
    """Show timeline summary for a date."""
    if not os.path.exists(TIMELINE_FILE):
        print(f"✗ {TIMELINE_FILE} 없음. `python timeline_sync.py sync` 먼저 실행.")
        return None

    data = load_timeline()
    segments = get_day_segments(data, target_date)
    summary = format_summary(segments, target_date)
    print_summary(summary)
    return summary


def _adb(cmd: str, timeout: int = 15) -> str:
    """Run ADB command, return stdout."""
    full = f"{ADB_CMD} {cmd}"
    env = os.environ.copy()
    env["MSYS_NO_PATHCONV"] = "1"
    try:
        r = subprocess.run(full, shell=True, capture_output=True, timeout=timeout, env=env)
        return r.stdout.decode("utf-8", errors="replace").strip()
    except (subprocess.TimeoutExpired, Exception):
        return ""


def _adb_ui_text() -> list:
    """Dump UI hierarchy and return list of (text, cx, cy) tuples."""
    import re
    xml = _adb('shell "uiautomator dump /sdcard/_ui.xml && cat /sdcard/_ui.xml"', timeout=10)
    results = []
    for m in re.finditer(r'text="([^"]+)".*?bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', xml):
        txt = m.group(1)
        if txt:
            cx = (int(m.group(2)) + int(m.group(4))) // 2
            cy = (int(m.group(3)) + int(m.group(5))) // 2
            results.append((txt, cx, cy))
    return results


def _adb_tap(x: int, y: int):
    _adb(f'shell "input tap {x} {y}"')


def _adb_find_tap(texts: list, ui: list = None) -> bool:
    """Find first matching text in UI and tap it. Returns True if found."""
    if ui is None:
        ui = _adb_ui_text()
    for txt, cx, cy in ui:
        for target in texts:
            if target in txt:
                _adb_tap(cx, cy)
                return True
    return False


def cmd_export():
    """폰에서 타임라인 데이터 내보내기 → pull → 로컬 저장."""
    import time

    print("=== 타임라인 내보내기 자동화 ===\n")

    # Step 0: 화면 켜기 + 잠금 해제
    print("  [0/7] 화면 켜기...")
    _adb('shell "input keyevent WAKEUP"')
    time.sleep(1)
    _adb('shell "input swipe 540 1800 540 800 300"')  # 스와이프 업
    time.sleep(1)
    _adb('shell "input text 0119"')  # PIN
    time.sleep(0.5)
    _adb('shell "input keyevent ENTER"')
    time.sleep(2)

    # Step 1: 홈 → 위치 설정 → 위치 서비스 화면
    print("  [1/7] 위치 설정 열기...")
    _adb('shell "input keyevent HOME"')
    time.sleep(1)
    _adb('shell "am start -a android.settings.LOCATION_SOURCE_SETTINGS --activity-clear-top"')
    time.sleep(3)

    # "위치 서비스" 하위 메뉴 진입 (위치 메인 → 위치 서비스)
    ui = _adb_ui_text()
    if any(t == "위치 서비스" for t, _, _ in ui) and not any(t == "타임라인" for t, _, _ in ui):
        print("  [1.5] 위치 서비스 진입...")
        for t, cx, cy in ui:
            if t == "위치 서비스":
                _adb_tap(cx, cy)
                break
        time.sleep(2)

    # Step 2: 타임라인 "탭하여 관리" → 계정 선택 → 타임라인 설정
    print("  [2/7] 타임라인 진입...")
    ui = _adb_ui_text()

    # "탭하여 관리" 중 타임라인 옆의 것 탭 (타임라인 y 근처의 "탭하여 관리")
    timeline_y = None
    for t, cx, cy in ui:
        if t == "타임라인":
            timeline_y = cy
            break

    if timeline_y:
        # 타임라인 바로 아래의 "탭하여 관리" 찾기
        for t, cx, cy in ui:
            if "탭하여 관리" in t and abs(cy - timeline_y) < 100:
                _adb_tap(cx, cy)
                break
    else:
        # 스크롤 후 재시도
        _adb('shell "input swipe 540 1500 540 500 500"')
        time.sleep(1)
        ui = _adb_ui_text()
        for t, cx, cy in ui:
            if t == "타임라인":
                timeline_y = cy
                break
        if timeline_y:
            for t, cx, cy in ui:
                if "탭하여 관리" in t and abs(cy - timeline_y) < 100:
                    _adb_tap(cx, cy)
                    break
        else:
            print("  ✗ 타임라인 메뉴를 찾을 수 없음")
            return False

    time.sleep(3)

    # 계정 선택 화면이 나오면 cjsghd8064 선택
    ui = _adb_ui_text()
    if any("계정 선택" in t for t, _, _ in ui):
        print("  [2.5] 계정 선택...")
        for t, cx, cy in ui:
            if "cjsghd8064" in t:
                _adb_tap(cx, cy)
                break
        time.sleep(3)
        ui = _adb_ui_text()

    # 타임라인 설정 화면 → "타임라인 데이터 내보내기" 탭
    ui_texts = [t for t, _, _ in ui]
    if any("타임라인 데이터 내보내기" in t for t in ui_texts):
        print("  [2.5] 타임라인 데이터 내보내기...")
        for t, cx, cy in ui:
            if "타임라인 데이터 내보내기" in t:
                _adb_tap(cx, cy)
                break
        time.sleep(3)
        ui = _adb_ui_text()
    elif any("내보내시겠습니까" in t for t in ui_texts):
        pass  # 이미 확인 다이얼로그
    else:
        # 스크롤해서 찾기
        _adb('shell "input swipe 540 1500 540 500 500"')
        time.sleep(1)
        ui = _adb_ui_text()
        for t, cx, cy in ui:
            if "내보내기" in t:
                _adb_tap(cx, cy)
                break
        time.sleep(3)
        ui = _adb_ui_text()

    # Step 3~5: 확인 → PIN 인증 → 저장 (uiautomator 기반 루프)
    # 각 단계에서 UI를 읽고 적절한 버튼을 탭
    for step in range(10):  # 최대 10번 반복
        time.sleep(2)
        ui = _adb_ui_text()
        ui_texts = {t: (cx, cy) for t, cx, cy in ui}

        if "계속" in ui_texts and any("내보내" in t for t in ui_texts):
            print("  [3/7] 내보내기 확인...")
            cx, cy = ui_texts["계속"]
            _adb_tap(cx, cy)
        elif "PIN 사용" in ui_texts:
            print("  [4/7] PIN 인증 (지문 → PIN 전환)...")
            cx, cy = ui_texts["PIN 사용"]
            _adb_tap(cx, cy)
        elif "현재 PIN을 입력하세요." in ui_texts:
            print("  [4/7] PIN 입력...")
            _adb('shell "input tap 540 749"')
            time.sleep(0.5)
            _adb('shell "input text 0119"')
            time.sleep(1)
            if "계속" in ui_texts:
                cx, cy = ui_texts["계속"]
                _adb_tap(cx, cy)
            else:
                # 계속 버튼 좌표 (고정)
                _adb_tap(765, 1348)
        elif "저장" in ui_texts and any("다운로드" in t for t in ui_texts):
            print("  [5/7] 파일 저장...")
            cx, cy = ui_texts["저장"]
            _adb_tap(cx, cy)
            time.sleep(5)
            break
        elif any("본인 인증" in t for t in ui_texts):
            print("  [4/7] 인증 화면 대기...")
            # 지문 대기 화면 — PIN 사용 버튼 탭
            for t, cx, cy in ui:
                if "PIN" in t:
                    _adb_tap(cx, cy)
                    break
        else:
            # 알 수 없는 화면 — 디버그 출력
            print(f"  (단계 {step}: 알 수 없는 화면)")
            for t, cx, cy in ui[:5]:
                print(f"    {t} ({cx},{cy})")
            if step >= 5:
                print("  ✗ 자동화 실패")
                return False

    # Step 6: Pull
    print("  [6/7] 파일 다운로드...")
    # 다운로드 폴더에서 pull (가장 최근 파일)
    # 한글 파일명 → 영문으로 복사 후 pull
    _adb("shell \"cp '/sdcard/Download/타임라인.json' /sdcard/Download/tl_export.json 2>/dev/null\"")
    time.sleep(2)

    env = os.environ.copy()
    env["MSYS_NO_PATHCONV"] = "1"
    result = subprocess.run(
        f'{ADB_CMD} pull /sdcard/Download/tl_export.json {TIMELINE_FILE}',
        shell=True, capture_output=True, timeout=120, env=env,
    )

    if result.returncode == 0:
        size = os.path.getsize(TIMELINE_FILE) / 1024 / 1024
        print(f"\n  ✓ 다운로드 완료: {TIMELINE_FILE} ({size:.1f}MB)")

        # Step 7: 정리 — 폰 임시 파일 삭제 + 화면 끄기
        print("  [7/7] 정리...")
        _adb('shell "rm -f /sdcard/Download/tl_export.json /sdcard/Download/타임라인.json"')
        _adb('shell "rm -f /sdcard/_ui.xml /sdcard/step*.xml /sdcard/auth_ui.xml /sdcard/pin_ui.xml /sdcard/after_pin.xml /sdcard/cur.xml"')
        _adb('shell "input keyevent HOME"')
        _adb('shell "input keyevent SLEEP"')  # 화면 끄기
        print("\n  ✓ 내보내기 완료!")
        return True
    else:
        print(f"\n  ✗ Pull 실패: {result.stderr[:200]}")
        _adb('shell "input keyevent HOME"')
        return False


def cmd_upload(target_date: str):
    """Upload daily summary to Firestore via CF endpoint."""
    if requests is None:
        print("✗ requests 라이브러리 필요: pip install requests")
        return False

    print(f"=== Upload: {target_date} ===\n")

    if not os.path.exists(TIMELINE_FILE):
        print(f"✗ {TIMELINE_FILE} 없음.")
        return False

    data = load_timeline()
    segments = get_day_segments(data, target_date)
    summary = format_summary(segments, target_date)

    if not summary["entries"]:
        print("업로드할 데이터 없음.")
        return False

    # Build compact payload for Firestore
    payload = {
        "movements": [],
        "outingTime": summary["outingTime"],
        "returnHome": summary["returnHome"],
        "totalDistance": summary["totalDistance"],
        "locations": summary["locationsVisited"],
        "entryCount": len(summary["entries"]),
        "syncedAt": datetime.now(KST).isoformat(),
    }

    # Compact movement list
    for e in summary["entries"]:
        m = {
            "time": e["time"],
            "type": e["type"],
            "label": e["label"],
            "duration": e["duration"],
        }
        if "distance" in e:
            m["distance"] = e["distance"]
        payload["movements"].append(m)

    # Upload via CF
    value_json = json.dumps(payload, ensure_ascii=False)
    field = f"timeline.{target_date}"

    params = urlencode({"q": "write", "doc": "today", "field": field, "value": value_json})
    url = f"{CF_BASE}?{params}"

    print(f"  필드: {field}")
    print(f"  항목 수: {len(payload['movements'])}")
    print(f"  총 거리: {fmt_distance(payload['totalDistance'])}")

    try:
        resp = requests.get(url, timeout=15)
        if resp.status_code == 200:
            print(f"\n  ✓ 업로드 성공")
            return True
        else:
            print(f"\n  ✗ HTTP {resp.status_code}: {resp.text[:200]}")
            return False
    except Exception as e:
        print(f"\n  ✗ 요청 실패: {e}")
        return False


# ── Main ────────────────────────────────────────────────────────────────

def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return

    cmd = sys.argv[1].lower()

    if cmd == "sync":
        cmd_sync()

    elif cmd == "export":
        cmd_export()

    elif cmd == "today":
        cmd_day(today_str())

    elif cmd == "upload":
        target = sys.argv[2] if len(sys.argv) > 2 else today_str()
        # Show summary first, then upload
        cmd_day(target)
        cmd_upload(target)

    else:
        # Assume it's a date
        target = sys.argv[1]
        # Validate date format
        try:
            datetime.strptime(target, "%Y-%m-%d")
        except ValueError:
            print(f"✗ 알 수 없는 명령/날짜: {target}")
            print("  사용법: python timeline_sync.py [sync|today|upload|YYYY-MM-DD]")
            return
        cmd_day(target)


if __name__ == "__main__":
    main()
