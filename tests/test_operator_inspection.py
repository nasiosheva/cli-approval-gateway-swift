#!/usr/bin/env python3
"""Tes CLI dengan audit dan direktori gateway sementara."""
import json
import os
from pathlib import Path
import pty
import select
import subprocess
import sys
import tempfile
import time
import unittest

BINARY = str(Path(sys.argv.pop(1)).resolve())


class InspectionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="gateway-inspection-")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name) / "data"
        self.env = os.environ.copy()
        self.env["GATEWAY_BASE_DIR_NAME"] = os.path.relpath(self.base, Path.home())

    def run_cli(self, *args):
        return subprocess.run([BINARY, *args], env=self.env, capture_output=True, text=True, timeout=15)

    def test_audit_filters_rotation_and_errors(self):
        self.assertEqual(self.run_cli("audit", "search").returncode, 0)
        self.assertFalse(self.base.exists())
        self.base.mkdir()
        entry = {"id": "old", "timestamp": "2026-01-02T00:30:00+01:00", "host": "alpha", "command": "echo {{pw:tag}}", "approved": True, "exitCode": 0}
        (self.base / "audit.log.1").write_text(json.dumps(entry) + "\n")
        entry.update(id="new", timestamp="2026-01-02T12:00:00Z", approved=False)
        (self.base / "audit.log").write_text(json.dumps(entry) + "\n")
        result = self.run_cli("audit", "search", "--host", "alpha", "--date", "2026-01-01", "--approved", "true")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["id"], "old")
        self.assertNotIn("new", result.stdout)
        self.assertIn("Tidak ada", self.run_cli("audit", "search", "--host", "other").stdout)
        for args in [("--date", "2026-02-30"), ("--approved", "yes"), ("--host",), ("--host", "a", "--host", "b")]:
            self.assertNotEqual(self.run_cli("audit", "search", *args).returncode, 0)
        (self.base / "audit.log").write_text("bad\n")
        self.assertNotEqual(self.run_cli("audit", "search").returncode, 0)
        (self.base / "audit.log").write_text("")
        self.assertEqual(self.run_cli("audit", "search").returncode, 0)

    def test_host_invalid(self):
        for host in ["", "-oProxyCommand=x", "bad\nhost"]:
            self.assertNotEqual(self.run_cli("host", "check", host).returncode, 0)
        self.assertFalse(self.base.exists())

    def test_empty_watcher_session(self):
        master, slave = pty.openpty()
        env = self.env.copy()
        env["GATEWAY_POLL_INTERVAL_SECONDS"] = "0.1"
        process = subprocess.Popen([BINARY], env=env, stdin=slave, stdout=slave, stderr=slave)
        os.close(slave)
        try:
            output = b""
            deadline = time.monotonic() + 10
            while process.poll() is None and time.monotonic() < deadline:
                if select.select([master], [], [], 0.1)[0]:
                    output += os.read(master, 8192)
                try:
                    os.write(master, b"s\n")
                except OSError:
                    break
                time.sleep(0.2)
            process.wait(timeout=2)
            while True:
                try:
                    chunk = os.read(master, 8192)
                    if not chunk: break
                    output += chunk
                except OSError:
                    break
            self.assertEqual(process.returncode, 0)
            self.assertIn(b"berhasil=0, gagal=0, ditolak=0", output)
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
            os.close(master)


if __name__ == "__main__":
    unittest.main()
