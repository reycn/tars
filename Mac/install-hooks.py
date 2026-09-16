#!/usr/bin/python3
"""Register tars-hook with Claude Code, Codex, opencode and pi: official lifecycle hooks.

  install-hooks.py install  [claude|codex|opencode|pi]
  install-hooks.py remove   [claude|codex|opencode|pi]
  install-hooks.py status              -> JSON {"claude": bool, ...}

Claude Code and Codex read hook entries from a JSON config: ownership is by exact
command path, so user hooks are never touched, and the file is backed up next to
itself before every write. opencode and pi load code instead, so Tars drops one
plugin/extension file of its own into their directory and removes just that file.
"""

from __future__ import annotations

import json
import os
import shutil
import stat
import sys
from pathlib import Path

HOME = Path.home()
# No spaces anywhere in these paths: Codex splits `command` on whitespace.
BIN = HOME / ".tars" / "bin"
HOOK_SOURCE = Path(__file__).resolve().with_name("hook.py")
CLAUDE_SETTINGS = HOME / ".claude" / "settings.json"
CODEX_HOOKS = HOME / ".codex" / "hooks.json"
OPENCODE_PLUGIN = Path(os.environ.get("XDG_CONFIG_HOME") or HOME / ".config") / "opencode" / "plugin" / "tars.js"
PI_EXTENSION = HOME / ".pi" / "agent" / "extensions" / "tars.ts"

CLAUDE_EVENTS = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure",
                 "PermissionRequest", "PermissionDenied", "Notification", "Elicitation", "ElicitationResult",
                 "Stop", "StopFailure", "SessionEnd"]
CODEX_EVENTS = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Stop", "SessionEnd"]

# Entries earlier Tars/Agent Eyes builds wrote; removed on install so nothing fires twice.
LEGACY_MARKERS = ("/Mac/mirror.py ",)

# Each provider gets its own hook copy: Codex drops `args`, so the file name carries the provider.
def _hook(name: str) -> Path:
    return BIN / ("tars-hook" if name == "claude" else f"tars-hook-{name}")


PROVIDERS = {
    "claude": dict(kind="json", path=CLAUDE_SETTINGS, hook=_hook("claude"), events=CLAUDE_EVENTS,
                   entry=lambda: {"type": "command", "command": str(_hook("claude")),
                                  "args": ["--provider", "claude-code"], "timeout": 5, "async": True}),
    "codex": dict(kind="json", path=CODEX_HOOKS, hook=_hook("codex"), events=CODEX_EVENTS,
                  entry=lambda: {"type": "command", "command": str(_hook("codex")), "timeout": 5}),
    "opencode": dict(kind="file", path=OPENCODE_PLUGIN, hook=_hook("opencode"),
                     source=Path(__file__).resolve().with_name("opencode-plugin.js")),
    "pi": dict(kind="file", path=PI_EXTENSION, hook=_hook("pi"),
               source=Path(__file__).resolve().with_name("pi-extension.ts")),
}


def _load(path: Path) -> dict:
    if not path.exists():
        return {}
    data = json.loads(path.read_text() or "{}")
    if not isinstance(data, dict):
        raise SystemExit(f"{path}: top level is not an object")
    return data


def _save(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        shutil.copy2(path, path.with_suffix(path.suffix + ".tars-backup"))
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
    os.replace(tmp, path)


def _ours(command: str, hook: Path) -> bool:
    return command.strip().strip("'\"").split(" ")[0] == str(hook) or any(m in command for m in LEGACY_MARKERS)


def _strip(groups: list, hook: Path) -> list:
    kept = []
    for group in groups:
        if not isinstance(group, dict):
            kept.append(group); continue
        hooks = [h for h in group.get("hooks", []) if not (isinstance(h, dict) and _ours(str(h.get("command", "")), hook))]
        if hooks:
            kept.append({**group, "hooks": hooks})
    return kept


def stage_binaries() -> None:
    BIN.mkdir(parents=True, exist_ok=True)
    for target in {spec["hook"] for spec in PROVIDERS.values()}:
        shutil.copyfile(HOOK_SOURCE, target)
        target.chmod(target.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)


def install(name: str) -> None:
    spec = PROVIDERS[name]
    stage_binaries()
    if spec["kind"] == "file":
        spec["path"].parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(spec["source"], spec["path"])
        return
    data = _load(spec["path"])
    hooks = data.setdefault("hooks", {})
    for event, groups in list(hooks.items()):
        hooks[event] = _strip(groups if isinstance(groups, list) else [], spec["hook"])
    for event in spec["events"]:
        hooks.setdefault(event, []).append({"hooks": [spec["entry"]()]})
    _save(spec["path"], data)


def remove(name: str) -> None:
    spec = PROVIDERS[name]
    if spec["kind"] == "file":
        spec["path"].unlink(missing_ok=True)
        return
    if not spec["path"].exists():
        return
    data = _load(spec["path"])
    hooks = data.get("hooks", {})
    for event, groups in list(hooks.items()):
        hooks[event] = _strip(groups if isinstance(groups, list) else [], spec["hook"])
        if not hooks[event]:
            del hooks[event]
    _save(spec["path"], data)


def installed(name: str) -> bool:
    spec = PROVIDERS[name]
    if not spec["path"].exists() or not spec["hook"].exists():
        return False
    if spec["kind"] == "file":  # a stale copy counts as off, so toggling back on refreshes it
        return spec["path"].read_bytes() == spec["source"].read_bytes()
    hooks = _load(spec["path"]).get("hooks", {})
    return all(any(isinstance(h, dict) and str(h.get("command", "")) == str(spec["hook"])
                   for g in hooks.get(event, []) if isinstance(g, dict) for h in g.get("hooks", []))
               for event in spec["events"])


def main(argv: list[str]) -> int:
    if len(argv) < 2 or argv[1] not in ("install", "remove", "status"):
        print(__doc__); return 2
    names = argv[2:] or list(PROVIDERS)
    if argv[1] == "status":
        print(json.dumps({n: installed(n) for n in PROVIDERS})); return 0
    for n in names:
        (install if argv[1] == "install" else remove)(n)
        print(f"{argv[1]}ed {n}: {PROVIDERS[n]['path']}")
    if argv[1] == "install" and "codex" in names:
        print("Codex only runs trusted hooks: open Codex, run /hooks, and trust the Tars entries.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
