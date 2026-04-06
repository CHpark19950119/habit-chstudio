"""루카 스터디카페 군포점 — 실시간 좌석 현황 조회"""
import urllib.request, json, sys

TOKEN = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJhbWJObyI6Ijk3QUY5MjRDLUFBMzItNEQ0MS1CRDhELUFEQTQ0MkUzMEU0QyIsImFtYlBob25lIjoiMDEwMjQzNTgwNjciLCJhbWJOYW1lIjoi67CV7LKc7ZmNIiwiYW1iQmlydGgiOiIxOTk1LTAxLTE5IiwiYW1iR2VuZGVyIjoibWFsZSIsImlhdCI6MTc3NDU0MjczMywiZXhwIjoxNzc3MTM0NzMzfQ.gO7ohevXlACzPE5gamg8xuxOjl5t23Z-e5vqS7wak34"
SP_NO = 1109
API = "https://data.space-force.kr"

def api_post(path, body=None):
    data = json.dumps(body or {}).encode()
    req = urllib.request.Request(f"{API}{path}", data=data, headers={
        "nuj-authorization": f"Bearer {TOKEN}",
        "Content-Type": "application/json",
    })
    return json.loads(urllib.request.urlopen(req, timeout=10).read())

def api_get(path):
    req = urllib.request.Request(f"{API}{path}", headers={
        "nuj-authorization": f"Bearer {TOKEN}",
    })
    return json.loads(urllib.request.urlopen(req, timeout=10).read())

def get_seats():
    """좌석 타입별 잔여 현황"""
    tickets = api_get(f"/app/shop/ticket/{SP_NO}")
    seat_types = []
    for category in tickets.get("data", {}).get("svcMenu", {}).values():
        for item in category.get("list", []):
            stc = item.get("SeatConfig", {})
            stc_no = stc.get("stcNo")
            stc_title = stc.get("stcTitle", "?")
            if stc_no and stc_no not in [s["stcNo"] for s in seat_types]:
                seat_types.append({"stcNo": stc_no, "title": stc_title})

    results = []
    for st in seat_types:
        try:
            resp = api_post("/app/seat/remain", {"spNo": SP_NO, "stcNo": st["stcNo"]})
            count = resp.get("data", {}).get("seat", {}).get("count", "?")
            results.append({"type": st["title"], "stcNo": st["stcNo"], "remain": count})
        except:
            results.append({"type": st["title"], "stcNo": st["stcNo"], "remain": "error"})

    return results

def get_position():
    """좌석 배치도 — 사용 중/빈 좌석"""
    resp = api_get(f"/app/shop/position/{SP_NO}")
    floors = resp.get("data", {}).get("position", [])
    summary = []
    for floor in floors:
        seats = floor.get("seats", [])
        if not seats:
            continue
        total = len(seats)
        occupied = sum(1 for s in seats if s.get("mbNo"))
        available = total - occupied
        name = floor.get("strName", "").encode('utf-8', errors='replace').decode('utf-8', errors='replace')
        summary.append({
            "floor": name or f"구역{floor.get('strNo','')}",
            "total": total,
            "occupied": occupied,
            "available": available,
        })
    return summary

if __name__ == "__main__":
    import sys
    if sys.platform == "win32":
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    print("루카 스터디카페 군포점")
    print("=" * 40)

    print("\n[좌석 타입별 잔여]")
    for s in get_seats():
        print(f"  {s['type']}: {s['remain']}석 남음")

    print("\n[구역별 현황]")
    for f in get_position():
        print(f"  {f['floor']}: {f['available']}/{f['total']}석 빈자리")

    print()
