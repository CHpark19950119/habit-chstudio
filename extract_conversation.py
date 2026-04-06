"""
대화 아카이브 추출 스크립트
- 현재 세션의 jsonl에서 user/assistant 메시지만 추출
- 핵심 요약 (피드백, 결정, 실수) 별도 추출
- conversation_archive/{date}_{time}.md 저장
"""

import json
import sys
import os
from datetime import datetime
from pathlib import Path

SESSIONS_DIR = Path(r"C:\Users\mla95\.claude\projects\C--dev-CHSTUDIO")
ARCHIVE_DIR = Path(r"C:\dev\CHSTUDIO\conversation_archive")
ARCHIVE_DIR.mkdir(exist_ok=True)


def extract_messages(jsonl_path: Path) -> list[dict]:
    """jsonl에서 user/assistant 메시지만 추출"""
    messages = []
    with open(jsonl_path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
            except json.JSONDecodeError:
                continue

            msg_type = entry.get("type", "")
            message = entry.get("message", {})
            role = message.get("role", "") if isinstance(message, dict) else ""

            # user 메시지
            if msg_type == "user":
                content = message.get("content", "") if isinstance(message, dict) else ""
                if isinstance(content, list):
                    # 멀티파트 메시지
                    texts = []
                    for part in content:
                        if isinstance(part, dict) and part.get("type") == "text":
                            texts.append(part.get("text", ""))
                    content = "\n".join(texts)
                elif isinstance(content, dict):
                    content = content.get("text", str(content))

                # 텔레그램 채널 메시지 추출
                if "<channel" in str(content):
                    import re
                    chan_match = re.findall(r'<channel[^>]*>(.*?)</channel>', str(content), re.DOTALL)
                    if chan_match:
                        content = "[텔레그램] " + " | ".join(chan_match)

                # system-reminder 제거
                if content and not content.strip().startswith("<system-reminder>"):
                    ts = entry.get("timestamp", "")
                    messages.append({"role": "user", "content": content[:2000], "ts": ts})

            # assistant 메시지
            elif msg_type == "assistant":
                content_parts = message.get("content", []) if isinstance(message, dict) else []
                if isinstance(content_parts, str):
                    text = content_parts
                elif isinstance(content_parts, list):
                    texts = []
                    for part in content_parts:
                        if isinstance(part, dict) and part.get("type") == "text":
                            texts.append(part.get("text", ""))
                    text = "\n".join(texts)
                else:
                    text = ""

                if text.strip():
                    ts = entry.get("timestamp", "")
                    messages.append({"role": "assistant", "content": text[:3000], "ts": ts})

    return messages


def format_conversation(messages: list[dict]) -> str:
    """메시지를 읽기 좋은 마크다운으로 변환"""
    lines = []
    for msg in messages:
        role = "나" if msg["role"] == "user" else "Claude"
        ts = msg.get("ts", "")
        if ts:
            try:
                dt = datetime.fromisoformat(ts.replace("Z", "+00:00"))
                ts_str = dt.strftime("%H:%M")
            except Exception:
                ts_str = ""
        else:
            ts_str = ""

        prefix = f"**{role}** {ts_str}" if ts_str else f"**{role}**"
        content = msg["content"].strip()
        # 너무 긴 내용은 줄임
        if len(content) > 1500:
            content = content[:1500] + "\n...(truncated)"
        lines.append(f"{prefix}\n{content}\n")

    return "\n---\n".join(lines)


def extract_current_session():
    """가장 최근 수정된 jsonl 파일에서 추출"""
    jsonl_files = sorted(SESSIONS_DIR.glob("*.jsonl"), key=lambda f: f.stat().st_mtime, reverse=True)
    if not jsonl_files:
        print("No jsonl files found")
        return

    latest = jsonl_files[0]
    print(f"Extracting from: {latest.name} ({latest.stat().st_size / 1048576:.1f}MB)")

    messages = extract_messages(latest)
    print(f"Extracted {len(messages)} messages")

    if not messages:
        print("No messages found")
        return

    # 대화 내용 저장
    now = datetime.now()
    filename = now.strftime("%Y-%m-%d_%H%M") + ".md"
    filepath = ARCHIVE_DIR / filename

    header = f"# 대화 아카이브 {now.strftime('%Y-%m-%d %H:%M')}\n"
    header += f"- 세션: {latest.name}\n"
    header += f"- 메시지 수: {len(messages)}\n"
    header += f"- 추출 시각: {now.isoformat()}\n\n---\n\n"

    conversation = format_conversation(messages)
    filepath.write_text(header + conversation, encoding="utf-8")

    size_kb = filepath.stat().st_size / 1024
    print(f"Saved: {filepath} ({size_kb:.0f}KB)")
    return str(filepath)


if __name__ == "__main__":
    extract_current_session()
