#!/usr/bin/env python3
"""Round-trips the installer against a throwaway HOME, so nothing touches real agent config."""
import importlib.util
import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

INSTALLER = Path(__file__).resolve().parents[1] / "Mac" / "install-hooks.py"


def load(home: Path):
    """Fresh import: the installer resolves every config path from HOME at import time."""
    with mock.patch.dict(os.environ, {"HOME": str(home), "XDG_CONFIG_HOME": str(home / ".config")}):
        spec = importlib.util.spec_from_file_location("install_hooks", INSTALLER)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module


class InstallTests(unittest.TestCase):
    def setUp(self):
        home = tempfile.TemporaryDirectory()
        self.addCleanup(home.cleanup)
        self.home = Path(home.name)
        self.mod = load(self.home)
        for spec in self.mod.PROVIDERS.values():  # nothing may escape the throwaway HOME
            self.assertTrue(str(spec["path"]).startswith(str(self.home)), spec["path"])

    def test_every_provider_installs_and_removes(self):
        for name in self.mod.PROVIDERS:
            self.assertFalse(self.mod.installed(name), name)
            self.mod.install(name)
            self.assertTrue(self.mod.installed(name), name)
            self.assertTrue(self.mod.PROVIDERS[name]["hook"].exists(), name)
            self.mod.remove(name)
            self.assertFalse(self.mod.installed(name), name)

    def test_file_providers_drop_one_file_and_refresh_when_stale(self):
        for name, spec in self.mod.PROVIDERS.items():
            if spec["kind"] != "file":
                continue
            self.mod.install(name)
            self.assertEqual(spec["path"].read_bytes(), spec["source"].read_bytes(), name)
            spec["path"].write_text("stale")
            self.assertFalse(self.mod.installed(name), name)  # so toggling back on rewrites it
            self.mod.remove(name)
            self.assertFalse(spec["path"].exists(), name)

    def test_json_providers_keep_foreign_hooks(self):
        theirs = {"type": "command", "command": "/usr/bin/true"}
        settings = self.mod.CLAUDE_SETTINGS
        settings.parent.mkdir(parents=True, exist_ok=True)
        settings.write_text(json.dumps({"hooks": {"Stop": [{"hooks": [theirs]}]}}))
        self.mod.install("claude")
        self.mod.remove("claude")
        self.assertEqual(json.loads(settings.read_text())["hooks"]["Stop"], [{"hooks": [theirs]}])


if __name__ == "__main__":
    unittest.main()
