#!/usr/bin/env python3
"""
Generate a weekly timeline report from Google Maps Timeline data.
Week: 2026-03-23 (Mon) to 2026-03-29 (Sun)
"""

import json
import math
import time
import urllib.request
import urllib.parse
from datetime import datetime, timedelta, timezone
from collections import defaultdict

# ── Config ──
TIMELINE_FILE = "C:/dev/CHSTUDIO/timeline_data.json"
OUTPUT_FILE = "C:/dev/CHSTUDIO/weekly_report.html"
HOME_LAT = 37.3137
HOME_LNG = 126.926
HOME_RADIUS_M = 200
WEEK_START = datetime(2026, 3, 23, 4, 0, 0, tzinfo=timezone(timedelta(hours=9)))  # 4AM boundary
WEEK_END = datetime(2026, 3, 30, 4, 0, 0, tzinfo=timezone(timedelta(hours=9)))
KST = timezone(timedelta(hours=9))

ACTIVITY_LABELS = {
    "WALKING": "도보",
    "IN_BUS": "버스",
    "IN_SUBWAY": "지하철",
    "IN_VEHICLE": "차량",
    "CYCLING": "자전거",
    "RUNNING": "달리기",
    "IN_TRAIN": "기차",
    "IN_TRAM": "트램",
    "IN_FERRY": "페리",
    "FLYING": "비행",
    "MOTORCYCLING": "오토바이",
    "SAILING": "항해",
    "SKIING": "스키",
    "STILL": "정지",
    "UNKNOWN_ACTIVITY_TYPE": "기타",
}

DAY_NAMES_KO = ["월", "화", "수", "목", "금", "토", "일"]

# ── Geocoding cache (persistent) ──
GEOCODE_CACHE_FILE = "C:/dev/CHSTUDIO/geocode_cache.json"
geocode_cache = {}

def load_geocode_cache():
    global geocode_cache
    try:
        with open(GEOCODE_CACHE_FILE, "r", encoding="utf-8") as f:
            raw = json.load(f)
            geocode_cache = {tuple(map(float, k.split(","))): v for k, v in raw.items()}
        print(f"Loaded {len(geocode_cache)} cached geocode results")
    except (FileNotFoundError, json.JSONDecodeError):
        geocode_cache = {}

def save_geocode_cache():
    raw = {f"{k[0]},{k[1]}": v for k, v in geocode_cache.items()}
    with open(GEOCODE_CACHE_FILE, "w", encoding="utf-8") as f:
        json.dump(raw, f, ensure_ascii=False, indent=2)


def haversine(lat1, lng1, lat2, lng2):
    """Distance in meters between two coords."""
    R = 6371000
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlam = math.radians(lng2 - lng1)
    a = math.sin(dphi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlam / 2) ** 2
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


def is_home(lat, lng):
    return haversine(lat, lng, HOME_LAT, HOME_LNG) < HOME_RADIUS_M


def parse_latlng(s):
    """Parse '37.3138998°, 126.9256182°' -> (lat, lng)"""
    parts = s.replace("°", "").replace("\u00b0", "").split(",")
    if len(parts) == 2:
        try:
            return float(parts[0].strip()), float(parts[1].strip())
        except ValueError:
            pass
    return None, None


GOOGLE_GEOCODE_KEY = "AIzaSyDIqOJ2Qh_wdwa8ZxVVzjZB-MecWjnog68"

# 자주 가는 장소 수동 매핑 (Nominatim/Google 부정확 보정)
KNOWN_PLACES = {
    (37.3137, 126.9260): "집",
    (37.5594, 126.9450): "이대앞 스터디카페",
    (37.3280, 126.9169): "대야미역",
    (37.3272, 126.9174): "대야미역",
    (37.3281, 126.9177): "대야미역",
    (37.3283, 126.9172): "대야미역",
    (37.4766, 126.9816): "사당역",
    (37.4777, 126.9822): "사당 방문",
    (37.4804, 126.9822): "사당 방문",
    (37.3167, 126.9239): "송부로",
    (37.5557, 126.9371): "신촌",
}


def _match_known_place(lat, lng, radius=0.001):
    """Check if coordinates match a known place (within ~100m)."""
    for (klat, klng), name in KNOWN_PLACES.items():
        if abs(lat - klat) < radius and abs(lng - klng) < radius:
            return name
    return None


def reverse_geocode(lat, lng):
    """Reverse geocode using known places → Google Geocoding API."""
    key = (round(lat, 4), round(lng, 4))
    if key in geocode_cache:
        return geocode_cache[key]

    # 1. 수동 매핑 우선
    known = _match_known_place(lat, lng)
    if known:
        geocode_cache[key] = known
        return known

    # 2. Google Geocoding API
    url = (
        f"https://maps.googleapis.com/maps/api/geocode/json?"
        f"latlng={lat},{lng}&key={GOOGLE_GEOCODE_KEY}&language=ko"
    )
    try:
        with urllib.request.urlopen(url, timeout=10) as resp:
            data = json.loads(resp.read().decode("utf-8"))

        if data.get("status") != "OK" or not data.get("results"):
            result = f"{lat:.4f}, {lng:.4f}"
            geocode_cache[key] = result
            return result

        r = data["results"][0]
        comps = r.get("address_components", [])

        # POI 이름 찾기
        poi = next((c["long_name"] for c in comps
                     if "point_of_interest" in c.get("types", [])
                     or "establishment" in c.get("types", [])), "")
        # 동/구 찾기
        dong = next((c["long_name"] for c in comps
                      if "sublocality_level_2" in c.get("types", [])), "")
        gu = next((c["long_name"] for c in comps
                    if "sublocality_level_1" in c.get("types", [])), "")

        if poi:
            result = f"{poi} ({dong})" if dong else poi
        elif dong:
            result = f"{dong}, {gu}" if gu else dong
        else:
            result = r.get("formatted_address", "")[:40]

        geocode_cache[key] = result
        return result
    except Exception as e:
        print(f"  Geocode failed for {lat},{lng}: {e}")
        result = f"{lat:.4f}, {lng:.4f}"
        geocode_cache[key] = result
        return result


def parse_time(s):
    """Parse ISO time string to datetime."""
    # Handle format like 2026-03-29T14:22:00.000+09:00
    s = s.strip()
    try:
        return datetime.fromisoformat(s)
    except ValueError:
        # Manual parse for older Python
        if "+" in s[10:]:
            main, tz_part = s.rsplit("+", 1)
        elif s.endswith("Z"):
            main = s[:-1]
            tz_part = "00:00"
        else:
            main = s
            tz_part = "09:00"
        # Remove fractional seconds
        if "." in main:
            main = main.split(".")[0]
        dt = datetime.strptime(main, "%Y-%m-%dT%H:%M:%S")
        tz_h, tz_m = map(int, tz_part.split(":"))
        return dt.replace(tzinfo=timezone(timedelta(hours=tz_h, minutes=tz_m)))


def get_logical_date(dt):
    """Get logical date with 4AM boundary."""
    if dt.hour < 4:
        return (dt - timedelta(days=1)).date()
    return dt.date()


def format_duration(seconds):
    """Format seconds to human readable duration."""
    if seconds < 0:
        seconds = 0
    hours = int(seconds // 3600)
    minutes = int((seconds % 3600) // 60)
    if hours > 0:
        return f"{hours}시간 {minutes}분"
    return f"{minutes}분"


def format_time(dt):
    """Format time as HH:MM."""
    return dt.strftime("%H:%M")


def format_distance(meters):
    """Format distance."""
    if meters >= 1000:
        return f"{meters / 1000:.1f}km"
    return f"{meters:.0f}m"


def main():
    print("Loading timeline data...")
    with open(TIMELINE_FILE, "r", encoding="utf-8") as f:
        data = json.load(f)

    segments = data["semanticSegments"]
    print(f"Total segments: {len(segments)}")

    # Filter to target week (visit + activity only, ignore raw timelinePath)
    week_segments = []
    for seg in segments:
        if "visit" not in seg and "activity" not in seg:
            continue
        st = parse_time(seg["startTime"])
        et = parse_time(seg["endTime"])
        # Include if overlaps with our week
        if et > WEEK_START and st < WEEK_END:
            week_segments.append(seg)

    print(f"Week segments (visit+activity): {len(week_segments)}")

    # ── Process segments into events ──
    events = []  # list of dicts
    unique_coords = {}  # (rounded_lat, rounded_lng) -> raw (lat, lng)

    for seg in week_segments:
        st = parse_time(seg["startTime"])
        et = parse_time(seg["endTime"])

        # Clamp to week boundaries
        if st < WEEK_START:
            st = WEEK_START
        if et > WEEK_END:
            et = WEEK_END

        if "visit" in seg:
            v = seg["visit"]
            tc = v.get("topCandidate", {})
            sem_type = tc.get("semanticType", "UNKNOWN")
            loc_str = tc.get("placeLocation", {}).get("latLng", "")
            lat, lng = parse_latlng(loc_str)

            is_home_visit = sem_type in ("HOME", "INFERRED_HOME")
            if lat is not None and not is_home_visit:
                is_home_visit = is_home(lat, lng)

            if lat is not None and not is_home_visit:
                key = (round(lat, 4), round(lng, 4))
                unique_coords[key] = (lat, lng)

            events.append({
                "type": "visit",
                "start": st,
                "end": et,
                "is_home": is_home_visit,
                "lat": lat,
                "lng": lng,
                "semantic_type": sem_type,
                "place_name": None,  # filled after geocoding
            })

        elif "activity" in seg:
            a = seg["activity"]
            tc = a.get("topCandidate", {})
            mode = tc.get("type", "UNKNOWN_ACTIVITY_TYPE")
            dist = a.get("distanceMeters", 0)
            events.append({
                "type": "activity",
                "start": st,
                "end": et,
                "mode": mode,
                "distance": dist,
            })

    # ── Deduplicate overlapping visits at same location ──
    # Some visits overlap (hierarchyLevel). Keep the one with longer duration.
    deduped = []
    skip = set()
    for i, ev in enumerate(events):
        if i in skip:
            continue
        if ev["type"] == "visit" and not ev["is_home"]:
            # Check if next event is a visit at very similar coords
            for j in range(i + 1, min(i + 3, len(events))):
                if j in skip:
                    continue
                ev2 = events[j]
                if ev2["type"] == "visit" and ev2.get("lat") and ev.get("lat"):
                    if haversine(ev["lat"], ev["lng"], ev2["lat"], ev2["lng"]) < 50:
                        # Same location, keep longer
                        dur_i = (ev["end"] - ev["start"]).total_seconds()
                        dur_j = (ev2["end"] - ev2["start"]).total_seconds()
                        if dur_j > dur_i:
                            skip.add(i)
                        else:
                            skip.add(j)
        if i not in skip:
            deduped.append(ev)

    events = deduped
    print(f"After dedup: {len(events)} events")

    # ── Reverse geocode unique non-home coordinates ──
    load_geocode_cache()
    print(f"Geocoding {len(unique_coords)} unique locations...")
    place_names = {}
    for key, (lat, lng) in unique_coords.items():
        name = reverse_geocode(lat, lng)
        place_names[key] = name
        print(f"  {lat:.4f}, {lng:.4f} -> {name}")

    save_geocode_cache()

    # Fill in place names
    for ev in events:
        if ev["type"] == "visit" and not ev["is_home"] and ev.get("lat"):
            key = (round(ev["lat"], 4), round(ev["lng"], 4))
            ev["place_name"] = place_names.get(key, f"{ev['lat']:.4f}, {ev['lng']:.4f}")

    # ── Group events by logical date, splitting multi-day events ──
    from datetime import date as date_type
    days = defaultdict(list)
    target_dates = [
        date_type(2026, 3, 23),
        date_type(2026, 3, 24),
        date_type(2026, 3, 25),
        date_type(2026, 3, 26),
        date_type(2026, 3, 27),
        date_type(2026, 3, 28),
        date_type(2026, 3, 29),
    ]

    def day_boundary(d):
        """Return 4AM KST datetime for the given date (start of logical day)."""
        return datetime(d.year, d.month, d.day, 4, 0, 0, tzinfo=KST)

    for ev in events:
        ev_start = ev["start"]
        ev_end = ev["end"]
        start_day = get_logical_date(ev_start)
        end_day = get_logical_date(ev_end)

        if start_day == end_day:
            # Single-day event
            if start_day in target_dates:
                days[start_day].append(ev)
        else:
            # Multi-day event: split across days
            current = start_day
            while current <= end_day:
                if current in target_dates:
                    # Compute the slice of this event for this day
                    slice_start = max(ev_start, day_boundary(current))
                    next_day = current + timedelta(days=1)
                    slice_end = min(ev_end, day_boundary(next_day))
                    if slice_start < slice_end:
                        sliced = dict(ev)
                        sliced["start"] = slice_start
                        sliced["end"] = slice_end
                        days[current].append(sliced)
                current += timedelta(days=1)

    # ── Compute per-day stats ──
    day_stats = {}
    for d in target_dates:
        d_events = sorted(days.get(d, []), key=lambda e: e["start"])
        total_distance = 0
        home_seconds = 0
        out_seconds = 0
        move_seconds = 0
        first_leave = None
        last_return = None
        visit_places = []
        mode_distances = defaultdict(float)

        for ev in d_events:
            dur = (ev["end"] - ev["start"]).total_seconds()
            if ev["type"] == "visit":
                if ev["is_home"]:
                    home_seconds += dur
                else:
                    out_seconds += dur
                    if ev.get("place_name"):
                        visit_places.append(ev["place_name"])
            elif ev["type"] == "activity":
                move_seconds += dur
                total_distance += ev.get("distance", 0)
                mode = ev.get("mode", "UNKNOWN_ACTIVITY_TYPE")
                mode_distances[mode] += ev.get("distance", 0)
                if first_leave is None:
                    first_leave = ev["start"]
                last_return = ev["end"]

        # Find actual first leave home and last return home
        for ev in d_events:
            if ev["type"] == "activity":
                first_leave = ev["start"]
                break
        for ev in reversed(d_events):
            if ev["type"] == "visit" and ev["is_home"]:
                last_return = ev["start"]
                break

        day_stats[d] = {
            "events": d_events,
            "total_distance": total_distance,
            "home_seconds": home_seconds,
            "out_seconds": out_seconds,
            "move_seconds": move_seconds,
            "first_leave": first_leave,
            "last_return": last_return,
            "visit_places": visit_places,
            "mode_distances": dict(mode_distances),
            "had_outing": total_distance > 1000,  # >1km = real outing
        }

    # ── Week summary ──
    total_distance_week = sum(s["total_distance"] for s in day_stats.values())
    outing_days = sum(1 for s in day_stats.values() if s["had_outing"])

    # All visited non-home places with counts
    all_places = defaultdict(int)
    for s in day_stats.values():
        for p in s["visit_places"]:
            all_places[p] += 1

    # Mode totals
    mode_totals = defaultdict(float)
    for s in day_stats.values():
        for mode, dist in s["mode_distances"].items():
            mode_totals[mode] += dist

    # Average leave/return times
    leave_times = [s["first_leave"] for s in day_stats.values() if s["first_leave"] and s["had_outing"]]
    return_times = [s["last_return"] for s in day_stats.values() if s["last_return"] and s["had_outing"]]

    avg_leave = None
    if leave_times:
        avg_minutes = sum(t.hour * 60 + t.minute for t in leave_times) / len(leave_times)
        avg_leave = f"{int(avg_minutes // 60):02d}:{int(avg_minutes % 60):02d}"

    avg_return = None
    if return_times:
        avg_minutes = sum(t.hour * 60 + t.minute for t in return_times) / len(return_times)
        avg_return = f"{int(avg_minutes // 60):02d}:{int(avg_minutes % 60):02d}"

    # Average outing duration
    outing_durations = []
    for s in day_stats.values():
        if s["had_outing"]:
            outing_durations.append(s["out_seconds"] + s["move_seconds"])
    avg_outing_dur = sum(outing_durations) / len(outing_durations) if outing_durations else 0

    # ── Max distance for bar chart ──
    max_dist = max((s["total_distance"] for s in day_stats.values()), default=1) or 1

    # ── Generate HTML ──
    print("Generating HTML...")
    html = generate_html(target_dates, day_stats, total_distance_week, outing_days,
                         all_places, mode_totals, avg_leave, avg_return, avg_outing_dur,
                         max_dist)

    with open(OUTPUT_FILE, "w", encoding="utf-8") as f:
        f.write(html)
    print(f"Report saved to {OUTPUT_FILE}")


def generate_html(target_dates, day_stats, total_distance_week, outing_days,
                  all_places, mode_totals, avg_leave, avg_return, avg_outing_dur,
                  max_dist):

    # Activity icon mapping
    mode_icons = {
        "WALKING": "🚶",
        "IN_BUS": "🚌",
        "IN_SUBWAY": "🚇",
        "IN_VEHICLE": "🚗",
        "CYCLING": "🚴",
        "RUNNING": "🏃",
        "IN_TRAIN": "🚆",
    }

    # ── Build day cards ──
    day_cards_html = ""
    for d in target_dates:
        stats = day_stats[d]
        dow = DAY_NAMES_KO[d.weekday()]
        date_str = f"{d.month}월 {d.day}일 ({dow})"

        # Day header class
        is_weekend = d.weekday() >= 5
        header_class = "day-header weekend" if is_weekend else "day-header"

        # Summary line
        if stats["had_outing"]:
            leave_str = format_time(stats["first_leave"]) if stats["first_leave"] else "-"
            return_str = format_time(stats["last_return"]) if stats["last_return"] else "-"
            summary = f"""
            <div class="day-summary">
                <div class="summary-item"><span class="summary-label">외출</span> {leave_str}</div>
                <div class="summary-item"><span class="summary-label">귀가</span> {return_str}</div>
                <div class="summary-item"><span class="summary-label">이동거리</span> {format_distance(stats['total_distance'])}</div>
                <div class="summary-item"><span class="summary-label">체류</span> {format_duration(stats['out_seconds'])}</div>
                <div class="summary-item"><span class="summary-label">이동</span> {format_duration(stats['move_seconds'])}</div>
            </div>"""
        else:
            summary = '<div class="day-summary"><span class="no-outing">종일 집</span></div>'

        # Timeline events
        timeline_html = ""
        home_total = 0
        d_events = sorted(stats["events"], key=lambda e: e["start"])

        for ev in d_events:
            dur = (ev["end"] - ev["start"]).total_seconds()
            time_str = format_time(ev["start"])

            if ev["type"] == "visit":
                if ev["is_home"]:
                    home_total += dur
                    continue  # Collapsed
                place = ev.get("place_name", "알 수 없는 장소")
                timeline_html += f"""
                <div class="timeline-event">
                    <div class="timeline-dot visit-dot"></div>
                    <div class="event-content">
                        <div class="event-time">{time_str} ~ {format_time(ev['end'])}</div>
                        <div class="event-title">📍 {html_escape(place)}</div>
                        <div class="event-detail">{format_duration(dur)} 체류</div>
                    </div>
                </div>"""
            elif ev["type"] == "activity":
                mode = ev.get("mode", "UNKNOWN_ACTIVITY_TYPE")
                mode_label = ACTIVITY_LABELS.get(mode, mode)
                icon = mode_icons.get(mode, "➡️")
                dist = ev.get("distance", 0)
                timeline_html += f"""
                <div class="timeline-event">
                    <div class="timeline-dot move-dot"></div>
                    <div class="event-content">
                        <div class="event-time">{time_str} ~ {format_time(ev['end'])}</div>
                        <div class="event-title">{icon} {mode_label}</div>
                        <div class="event-detail">{format_distance(dist)} · {format_duration(dur)}</div>
                    </div>
                </div>"""

        # Add home summary at bottom
        if home_total > 0:
            timeline_html += f"""
            <div class="timeline-event home-event">
                <div class="timeline-dot home-dot"></div>
                <div class="event-content">
                    <div class="event-title">🏠 집</div>
                    <div class="event-detail">총 {format_duration(home_total)}</div>
                </div>
            </div>"""

        if not timeline_html.strip():
            timeline_html = '<div class="no-data">데이터 없음</div>'

        day_cards_html += f"""
        <div class="day-card">
            <div class="{header_class}">{date_str}</div>
            {summary}
            <div class="timeline">
                {timeline_html}
            </div>
        </div>"""

    # ── Bar chart data ──
    bar_chart_html = ""
    for d in target_dates:
        stats = day_stats[d]
        dist = stats["total_distance"]
        pct = (dist / max_dist * 100) if max_dist > 0 else 0
        dow = DAY_NAMES_KO[d.weekday()]
        dist_label = format_distance(dist) if dist > 100 else "-"
        bar_class = "bar-fill weekend-bar" if d.weekday() >= 5 else "bar-fill"
        bar_chart_html += f"""
        <div class="bar-row">
            <div class="bar-label">{d.day}({dow})</div>
            <div class="bar-track">
                <div class="{bar_class}" style="width: {pct:.1f}%"></div>
            </div>
            <div class="bar-value">{dist_label}</div>
        </div>"""

    # ── Places list ──
    places_html = ""
    for place, count in sorted(all_places.items(), key=lambda x: -x[1]):
        places_html += f'<div class="place-item"><span class="place-name">📍 {html_escape(place)}</span><span class="place-count">{count}회</span></div>'

    if not places_html:
        places_html = '<div class="no-data">방문 장소 없음</div>'

    # ── Mode breakdown ──
    total_mode_dist = sum(mode_totals.values()) or 1
    mode_html = ""
    mode_colors = {
        "WALKING": "#4ade80",
        "IN_BUS": "#60a5fa",
        "IN_SUBWAY": "#f472b6",
        "IN_VEHICLE": "#fbbf24",
    }
    # Sort by distance desc
    for mode, dist in sorted(mode_totals.items(), key=lambda x: -x[1]):
        label = ACTIVITY_LABELS.get(mode, mode)
        icon = mode_icons.get(mode, "➡️")
        pct = dist / total_mode_dist * 100
        color = mode_colors.get(mode, "#94a3b8")
        mode_html += f"""
        <div class="mode-item">
            <div class="mode-header">
                <span>{icon} {label}</span>
                <span>{format_distance(dist)} ({pct:.0f}%)</span>
            </div>
            <div class="mode-bar-track">
                <div class="mode-bar-fill" style="width: {pct:.1f}%; background: {color}"></div>
            </div>
        </div>"""

    # ── Final HTML ──
    return f"""<!DOCTYPE html>
<html lang="ko">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>주간 이동 보고서 — 2026.03.23~03.29</title>
<style>
* {{ margin: 0; padding: 0; box-sizing: border-box; }}
body {{
    background: #1a1a2e;
    color: #e0e0e0;
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Noto Sans KR', sans-serif;
    line-height: 1.6;
    padding: 16px;
    max-width: 800px;
    margin: 0 auto;
}}
h1 {{
    text-align: center;
    color: #e94560;
    font-size: 1.5rem;
    margin-bottom: 4px;
}}
.subtitle {{
    text-align: center;
    color: #8892b0;
    font-size: 0.85rem;
    margin-bottom: 24px;
}}
.section-title {{
    color: #e94560;
    font-size: 1.1rem;
    font-weight: 700;
    margin: 24px 0 12px 0;
    padding-left: 8px;
    border-left: 3px solid #e94560;
}}

/* Summary cards */
.summary-grid {{
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(140px, 1fr));
    gap: 12px;
    margin-bottom: 20px;
}}
.stat-card {{
    background: #16213e;
    border-radius: 12px;
    padding: 16px;
    text-align: center;
}}
.stat-value {{
    font-size: 1.6rem;
    font-weight: 700;
    color: #e94560;
}}
.stat-label {{
    font-size: 0.78rem;
    color: #8892b0;
    margin-top: 2px;
}}

/* Bar chart */
.bar-chart {{
    background: #16213e;
    border-radius: 12px;
    padding: 16px;
    margin-bottom: 20px;
}}
.bar-row {{
    display: flex;
    align-items: center;
    margin-bottom: 8px;
    gap: 8px;
}}
.bar-label {{
    width: 52px;
    font-size: 0.82rem;
    color: #8892b0;
    text-align: right;
    flex-shrink: 0;
}}
.bar-track {{
    flex: 1;
    height: 22px;
    background: #0f3460;
    border-radius: 6px;
    overflow: hidden;
}}
.bar-fill {{
    height: 100%;
    background: linear-gradient(90deg, #e94560, #c23152);
    border-radius: 6px;
    transition: width 0.3s;
    min-width: 2px;
}}
.weekend-bar {{
    background: linear-gradient(90deg, #f472b6, #e94560);
}}
.bar-value {{
    width: 60px;
    font-size: 0.82rem;
    color: #ccd6f6;
    text-align: left;
    flex-shrink: 0;
}}

/* Places */
.places-card {{
    background: #16213e;
    border-radius: 12px;
    padding: 16px;
    margin-bottom: 20px;
}}
.place-item {{
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 8px 0;
    border-bottom: 1px solid #0f3460;
}}
.place-item:last-child {{ border-bottom: none; }}
.place-name {{
    font-size: 0.9rem;
    color: #ccd6f6;
}}
.place-count {{
    font-size: 0.82rem;
    color: #e94560;
    font-weight: 600;
}}

/* Mode breakdown */
.mode-card {{
    background: #16213e;
    border-radius: 12px;
    padding: 16px;
    margin-bottom: 20px;
}}
.mode-item {{ margin-bottom: 10px; }}
.mode-header {{
    display: flex;
    justify-content: space-between;
    font-size: 0.88rem;
    margin-bottom: 4px;
    color: #ccd6f6;
}}
.mode-bar-track {{
    height: 8px;
    background: #0f3460;
    border-radius: 4px;
    overflow: hidden;
}}
.mode-bar-fill {{
    height: 100%;
    border-radius: 4px;
}}

/* Time analysis */
.time-card {{
    background: #16213e;
    border-radius: 12px;
    padding: 16px;
    margin-bottom: 20px;
}}
.time-row {{
    display: flex;
    justify-content: space-between;
    padding: 6px 0;
    border-bottom: 1px solid #0f3460;
    font-size: 0.9rem;
}}
.time-row:last-child {{ border-bottom: none; }}
.time-label {{ color: #8892b0; }}
.time-value {{ color: #ccd6f6; font-weight: 600; }}

/* Day cards */
.day-card {{
    background: #16213e;
    border-radius: 12px;
    margin-bottom: 16px;
    overflow: hidden;
}}
.day-header {{
    background: #0f3460;
    padding: 12px 16px;
    font-weight: 700;
    font-size: 1rem;
    color: #ccd6f6;
}}
.day-header.weekend {{
    background: linear-gradient(90deg, #0f3460, #1a1040);
    color: #f472b6;
}}
.day-summary {{
    display: flex;
    flex-wrap: wrap;
    gap: 12px;
    padding: 12px 16px;
    border-bottom: 1px solid #0f3460;
    font-size: 0.82rem;
}}
.summary-item {{
    color: #ccd6f6;
}}
.summary-label {{
    color: #8892b0;
    margin-right: 4px;
}}
.no-outing {{
    color: #8892b0;
    font-style: italic;
}}

/* Timeline */
.timeline {{
    padding: 12px 16px 12px 32px;
    position: relative;
}}
.timeline::before {{
    content: '';
    position: absolute;
    left: 23px;
    top: 12px;
    bottom: 12px;
    width: 2px;
    background: #0f3460;
}}
.timeline-event {{
    position: relative;
    padding: 6px 0 6px 20px;
}}
.timeline-dot {{
    position: absolute;
    left: -15px;
    top: 12px;
    width: 10px;
    height: 10px;
    border-radius: 50%;
    border: 2px solid #0f3460;
}}
.visit-dot {{
    background: #e94560;
    border-color: #e94560;
}}
.move-dot {{
    background: #60a5fa;
    border-color: #60a5fa;
}}
.home-dot {{
    background: #4ade80;
    border-color: #4ade80;
}}
.event-content {{}}
.event-time {{
    font-size: 0.75rem;
    color: #8892b0;
}}
.event-title {{
    font-size: 0.9rem;
    color: #ccd6f6;
    font-weight: 600;
}}
.event-detail {{
    font-size: 0.8rem;
    color: #8892b0;
}}
.home-event {{
    opacity: 0.7;
    margin-top: 4px;
    padding-top: 8px;
    border-top: 1px dashed #0f3460;
}}
.no-data {{
    color: #8892b0;
    font-style: italic;
    font-size: 0.85rem;
    padding: 8px 0;
}}

/* Footer */
.footer {{
    text-align: center;
    color: #4a5568;
    font-size: 0.75rem;
    margin-top: 32px;
    padding-bottom: 16px;
}}

/* Responsive */
@media (max-width: 480px) {{
    body {{ padding: 8px; }}
    h1 {{ font-size: 1.2rem; }}
    .summary-grid {{ grid-template-columns: repeat(2, 1fr); }}
    .day-summary {{ gap: 8px; }}
    .bar-label {{ width: 44px; font-size: 0.75rem; }}
    .bar-value {{ width: 50px; font-size: 0.75rem; }}
}}
</style>
</head>
<body>

<h1>주간 이동 보고서</h1>
<div class="subtitle">2026년 3월 23일 (월) ~ 3월 29일 (일)</div>

<!-- Week Summary -->
<div class="summary-grid">
    <div class="stat-card">
        <div class="stat-value">{outing_days}</div>
        <div class="stat-label">외출일</div>
    </div>
    <div class="stat-card">
        <div class="stat-value">{format_distance(total_distance_week)}</div>
        <div class="stat-label">총 이동거리</div>
    </div>
    <div class="stat-card">
        <div class="stat-value">{avg_leave or '-'}</div>
        <div class="stat-label">평균 외출시간</div>
    </div>
    <div class="stat-card">
        <div class="stat-value">{avg_return or '-'}</div>
        <div class="stat-label">평균 귀가시간</div>
    </div>
    <div class="stat-card">
        <div class="stat-value">{format_duration(avg_outing_dur)}</div>
        <div class="stat-label">평균 외출 지속시간</div>
    </div>
</div>

<!-- Daily distance bar chart -->
<div class="section-title">일별 이동거리</div>
<div class="bar-chart">
    {bar_chart_html}
</div>

<!-- Transport mode breakdown -->
<div class="section-title">이동수단 비율</div>
<div class="mode-card">
    {mode_html}
</div>

<!-- Visited places -->
<div class="section-title">주요 방문 장소</div>
<div class="places-card">
    {places_html}
</div>

<!-- Daily details -->
<div class="section-title">일별 상세</div>
{day_cards_html}

<div class="footer">
    CHSTUDIO Weekly Timeline Report · Generated {datetime.now().strftime('%Y-%m-%d %H:%M')}
</div>

</body>
</html>"""


def html_escape(s):
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace('"', "&quot;")


if __name__ == "__main__":
    main()
