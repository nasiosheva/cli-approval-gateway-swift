#!/usr/bin/env python3
"""Integration checks using a temporary gateway directory."""
import fcntl
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

BINARY = str(Path(sys.argv.pop(1)).resolve()) if len(sys.argv) > 1 else "cli-approval-gateway"


class RequestStatusTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="gateway-status-")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name) / "data"
        self.env = os.environ.copy()
        self.env["GATEWAY_BASE_DIR_NAME"] = os.path.relpath(self.base, Path.home())

    def status(self, *args):
        return subprocess.run([BINARY, "status", *args], env=self.env, text=True,
                              capture_output=True, timeout=10)

    def write(self, directory, name, value=""):
        folder = self.base / directory
        folder.mkdir(parents=True, exist_ok=True)
        (folder / name).write_text(value)

    def test_invalid_missing_and_no_side_effects(self):
        for args in [(), ("",), ("..",), ("../outside",), ("a/b",), ("a\nb",), ("id", "extra")]:
            self.assertNotEqual(self.status(*args).returncode, 0, args)
        self.assertNotEqual(self.status("missing").returncode, 0)
        self.assertFalse(self.base.exists())

    def test_priority_and_processing_stage(self):
        self.write("requests", "one.sh")
        self.assertIn("menunggu", self.status("one").stdout)
        self.write("processed", "one.sh")
        self.assertIn("hasil tidak tersedia", self.status("one").stdout)
        self.write("processing", "one.sh")
        self.assertIn("sedang diproses", self.status("one").stdout)
        self.write("processing", "one.status.json", json.dumps({"id": "one", "stage": "ssh-started", "host": "example", "timestamp": "now"}))
        self.assertIn("ssh-started", self.status("one").stdout)
        self.write("responses", "one.json", json.dumps({"id": "one", "approved": True, "exitCode": None, "status": "execution-unknown"}))
        result = self.status("one")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("execution-unknown", result.stdout)
        self.assertIn("Approval: true", result.stdout)
        self.assertNotIn("Exit code:", result.stdout)
        self.write("responses", "one.json", json.dumps({"id": "one", "approved": True, "exitCode": 7}))
        self.assertIn("Exit code: 7", self.status("one").stdout)

    def test_corrupt_state_and_read_only_with_lock(self):
        self.write("processing", "one.sh")
        self.write("processing", "one.status.json", "broken")
        self.assertNotEqual(self.status("one").returncode, 0)
        self.write("responses", "one.json", "broken")
        self.assertNotEqual(self.status("one").returncode, 0)
        self.write("responses", "one.json", json.dumps({"id": "other"}))
        self.assertNotEqual(self.status("one").returncode, 0)
        self.write("responses", "one.json", json.dumps({"id": "one", "approved": False, "exitCode": None}))
        lock_path = self.base / "watcher.lock"
        with lock_path.open("w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            before = {str(p.relative_to(self.base)): p.read_bytes() for p in self.base.rglob("*") if p.is_file()}
            result = self.status("one")
            after = {str(p.relative_to(self.base)): p.read_bytes() for p in self.base.rglob("*") if p.is_file()}
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Approval: false", result.stdout)
        self.assertEqual(before, after)


if __name__ == "__main__":
    unittest.main()
