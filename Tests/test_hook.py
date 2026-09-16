#!/usr/bin/env python3
import hashlib
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "Mac"))
import hook


class HookTests(unittest.TestCase):
    def test_states_and_privacy(self):
        ev = hook.normalize({"hook_event_name": "PreToolUse", "session_id": "x", "tool_name": "Bash",
                             "tool_input": {"command": "rm -rf /", "description": "Clean"}}, "claude")
        self.assertEqual(ev, {"session": hashlib.sha256(b"claude:x").hexdigest()[:24], "state": "working", "detail": "Bash: Clean"})
        self.assertEqual(hook.normalize({"hook_event_name": "Stop", "session_id": "x", "last_assistant_message": "Done.\n\nAll good"}, "claude")["detail"], "Done. All good")
        self.assertEqual(hook.normalize({"hook_event_name": "SessionEnd", "session_id": "x"}, "claude"), {"session": hashlib.sha256(b"claude:x").hexdigest()[:24], "state": "ended"})

    def test_questions_are_approval(self):
        ev = hook.normalize({"hook_event_name": "PreToolUse", "session_id": "x", "tool_name": "AskUserQuestion",
                             "tool_input": {"questions": [{"question": "Ship it?"}]}}, "claude")
        self.assertEqual((ev["state"], ev["detail"]), ("approval", "AskUserQuestion: Ship it?"))
        self.assertEqual(hook.normalize({"hook_event_name": "PermissionRequest", "session_id": "x", "tool_name": "Edit"}, "codex")["state"], "approval")
        self.assertEqual(hook.normalize({"hook_event_name": "Notification", "notification_type": "permission_prompt", "session_id": "x"}, "claude")["state"], "approval")

    def test_unmapped_ignored(self):
        self.assertIsNone(hook.normalize({"hook_event_name": "Whatever", "session_id": "x"}, "claude"))
        self.assertIsNone(hook.normalize({"hook_event_name": "Notification", "notification_type": "other", "session_id": "x"}, "claude"))

    def test_provider_from_args_or_name(self):
        self.assertEqual(hook.provider(["/x/tars-hook", "--provider", "claude-code"]), "claude")
        self.assertEqual(hook.provider(["/x/tars-hook-codex"]), "codex")
        self.assertEqual(hook.provider(["/x/tars-hook"]), "claude")

    def test_clip(self):
        self.assertTrue(hook.normalize({"hook_event_name": "UserPromptSubmit", "session_id": "x", "prompt": "a" * 300}, "claude")["detail"].endswith("…"))


if __name__ == "__main__":
    unittest.main()
