"""
수학 협업 도구 — o3 풀이 + Claude 설명/첨삭
사용법: python math_collab.py "문제 텍스트"
"""
import os, sys, io, json
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')

from openai import OpenAI

OPENAI_KEY = os.environ.get("OPENAI_API_KEY", "")
if not OPENAI_KEY:
    raise RuntimeError("OPENAI_API_KEY 환경변수가 없다. 셸에서 export 후 재실행.")

def solve_with_o3(problem: str) -> str:
    """o3-mini로 수학 문제 풀이"""
    client = OpenAI(api_key=OPENAI_KEY)
    resp = client.chat.completions.create(
        model="o3-mini",
        messages=[
            {"role": "system", "content": (
                "너는 수학 문제를 푸는 전문가야. "
                "풀이를 단계별로 상세히 작성해. "
                "각 단계마다 왜 그렇게 하는지 이유를 설명해. "
                "최종 답을 명확히 표시해. "
                "한국어로 답해."
            )},
            {"role": "user", "content": problem}
        ],
        max_completion_tokens=2000,
    )
    return resp.choices[0].message.content

def generate_problems(topic: str, level: str = "초등", count: int = 5) -> str:
    """o3-mini로 수리 논술 문제 생성"""
    client = OpenAI(api_key=OPENAI_KEY)
    resp = client.chat.completions.create(
        model="o3-mini",
        messages=[
            {"role": "system", "content": (
                f"너는 {level} 수준의 수리 논술 문제를 출제하는 전문가야. "
                "문제는 계산이 아닌 논리적 사고를 요구해야 해. "
                "서술형으로 풀이 과정을 쓰게 해. "
                "각 문제마다 난이도(★~★★★)를 표시해. "
                "한국어로 출제해."
            )},
            {"role": "user", "content": f"주제: {topic}\n{count}문제 출제해줘."}
        ],
        max_completion_tokens=2000,
    )
    return resp.choices[0].message.content

def review_solution(problem: str, student_solution: str) -> str:
    """o3-mini로 학생 풀이 첨삭"""
    client = OpenAI(api_key=OPENAI_KEY)
    resp = client.chat.completions.create(
        model="o3-mini",
        messages=[
            {"role": "system", "content": (
                "너는 수학 첨삭 전문가야. 학생의 풀이를 검토해서:\n"
                "1. 맞는 부분 칭찬\n"
                "2. 틀린 부분 지적 (왜 틀렸는지)\n"
                "3. 논리적 비약이 있으면 지적\n"
                "4. 더 나은 풀이 방법이 있으면 제안\n"
                "5. 점수 (10점 만점)\n"
                "한국어로 답해. 냉정하되 격려도 해."
            )},
            {"role": "user", "content": f"[문제]\n{problem}\n\n[학생 풀이]\n{student_solution}"}
        ],
        max_completion_tokens=1500,
    )
    return resp.choices[0].message.content

if __name__ == "__main__":
    if len(sys.argv) > 1:
        problem = " ".join(sys.argv[1:])
        print("=== o3-mini 풀이 ===\n")
        result = solve_with_o3(problem)
        print(result)
    else:
        print("사용법: python math_collab.py '문제 텍스트'")
        print("또는 import해서 solve_with_o3(), generate_problems(), review_solution() 사용")
