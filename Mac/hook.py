#!/usr/bin/python3
"""tars-hook: the observer agents invoke on lifecycle events.

Contract (same as codestatus): never block the agent, never fail it, never leak.
Reads one hook payload from stdin, projects it to {session, state, detail} and
pushes it to the Tars server on loopback with a 50 ms budget. Always exits 0.
"""

from __future__ import annotations

import hashlib
import json
import socket
import sys
from collections.abc import Sequence
from typing import Any

MAX_INPUT = 4 * 1024 * 1024
SERVER_ADDRESS = ("127.0.0.1", 17894)
SERVER_TIMEOUT = 0.05
DETAIL_LIMIT = 160

# Claude Code and Codex share the hook vocabulary; Codex has a subset.
_HOOK_STATES = {
    "sessionstart": "waiting",
    "userpromptsubmit": "working",
    "pretooluse": "working",
    "posttooluse": "working",
    "posttoolusefailure": "working",
    "posttoolbatch": "working",
    "precompact": "working",
    "postcompact": "working",
    "permissionrequest": "approval",
    "permissiondenied": "working",
    "elicitation": "approval",
    "elicitationresult": "working",
    "subagentstop": "working",
    "stop": "completed",
    "stopfailure": "waiting",
    "sessionend": "ended",
}
# Tools that block on the person: a question is not work in progress.
_ASKS_USER = {"askuserquestion", "exitplanmode"}


def _text(value: Any) -> str | None:
    if isinstance(value, str) and value.strip():
        return value.strip()
    return None


def _clip(value: Any) -> str | None:
    text = _text(value)
    if text is None:
        return None
    text = " ".join(text.split())
    return text[: DETAIL_LIMIT - 1] + "…" if len(text) > DETAIL_LIMIT else text


def provider(argv: Sequence[str]) -> str:
    """`--provider X` from Claude's `args`; other agents drop args, so `tars-hook-<name>` carries it."""
    args = list(argv)
    for index, argument in enumerate(args[1:], 1):
        if argument == "--provider" and index + 1 < len(args):
            return args[index + 1].lower().replace("-code", "")
    name = (args[0] if args else "").rsplit("/", 1)[-1]
    suffix = name[len("tars-hook-"):] if name.startswith("tars-hook-") else ""
    return suffix or "claude"


def state_for(event: dict[str, Any]) -> str | None:
    hook = (_text(event.get("hook_event_name")) or "").lower()
    if hook == "notification":
        kind = _text(event.get("notification_type"))
        return {"permission_prompt": "approval", "idle_prompt": "waiting"}.get(kind or "")
    if hook in ("pretooluse", "permissionrequest") and (_text(event.get("tool_name")) or "").lower() in _ASKS_USER:
        return "approval"
    if _text(event.get("type")) == "agent-turn-complete":  # Codex notify
        return "completed"
    return _HOOK_STATES.get(hook)


def detail_for(event: dict[str, Any], state: str) -> str | None:
    """One human line: current task, approval question, or finished task."""
    tool = _text(event.get("tool_name"))
    tool_input = event.get("tool_input") if isinstance(event.get("tool_input"), dict) else {}
    tool_line = None
    if tool is not None:
        arg = (_text(tool_input.get("description")) or _text(tool_input.get("command"))
               or _text(tool_input.get("file_path")) or _text(tool_input.get("pattern"))
               or _text(tool_input.get("prompt")))
        if tool.lower() in _ASKS_USER:
            questions = tool_input.get("questions")
            if isinstance(questions, list) and questions and isinstance(questions[0], dict):
                arg = _text(questions[0].get("question")) or arg
        tool_line = f"{tool}: {arg}" if arg else tool
    if state == "approval":
        return _clip(_text(event.get("message")) or tool_line)
    if state == "completed":
        return _clip(event.get("last_assistant_message") or event.get("last-assistant-message"))
    if state == "working":
        return _clip(_text(event.get("prompt")) or tool_line)
    return None


def normalize(event: dict[str, Any], source: str) -> dict[str, str] | None:
    """Privacy-safe projection, or None for events with no state meaning."""
    if not isinstance(event, dict):
        return None
    state = state_for(event)
    if state is None:
        return None
    key = _text(event.get("session_id")) or _text(event.get("thread_id")) or _text(event.get("thread-id")) or "unknown"
    result = {"session": hashlib.sha256(f"{source}:{key}".encode()).hexdigest()[:24], "state": state}
    detail = detail_for(event, state)
    if detail is not None:
        result["detail"] = detail
    return result


def send(payload: dict[str, str]) -> None:
    try:
        data = json.dumps(payload, separators=(",", ":"), ensure_ascii=True).encode() + b"\n"
        if len(data) > 2048:
            return
        with socket.create_connection(SERVER_ADDRESS, timeout=SERVER_TIMEOUT) as connection:
            connection.sendall(data)
    except Exception:
        return


def main(argv: Sequence[str] | None = None) -> int:
    args = list(sys.argv if argv is None else argv)
    try:
        raw = sys.stdin.buffer.read(MAX_INPUT + 1)
        if len(raw) <= MAX_INPUT:
            event = json.loads(raw.decode("utf-8", "replace") or "{}")
            projected = normalize(event, provider(args))
            if projected is not None:
                send(projected)
    except Exception:
        pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
