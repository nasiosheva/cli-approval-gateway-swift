#!/usr/bin/env python3
"""CLI integration tests; all gateway data lives in a temporary directory.

Run: python3 tests/test_doctor_and_clear.py /path/to/cli-approval-gateway
"""
import fcntl
import os
from pathlib import Path
import pty
import select
import subprocess
import sys
import tempfile
import unittest


BINARY = str(Path(sys.argv.pop(1)).resolve()) if len(sys.argv) > 1 else "cli-approval-gateway"


class GatewayCLI(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="gateway-cli-test-")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name) / "data"
        self.env = os.environ.copy()
        for key in list(self.env):
            if key.startswith("GATEWAY_"):
                del self.env[key]
        self.env["GATEWAY_BASE_DIR_NAME"] = os.path.relpath(self.base, Path.home())
        self.env["GATEWAY_KEYCHAIN_SERVICE_NAME"] = "com.cli-approval-gateway.integration-test-no-items"

    def prepare(self):
        for name in ("requests", "processing", "responses", "processed"):
            (self.base / name).mkdir(parents=True, exist_ok=True)
        (self.base / "responses" / "sample.json").write_text("response")
        (self.base / "responses" / "keep.txt").write_text("keep")
        (self.base / "audit.log").write_text("audit")

    def run_cli(self, *args, env=None):
        return subprocess.run([BINARY, *args], env=env or self.env, input="", text=True,
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=10)

    def interactive(self, command, answer):
        master, slave = pty.openpty()
        try:
            process = subprocess.Popen([BINARY, command], env=self.env, stdin=slave,
                                       stdout=slave, stderr=slave, close_fds=True)
            os.close(slave)
            slave = -1
            output = b""
            while b"[y/N]" not in output:
                ready, _, _ = select.select([master], [], [], 10)
                if not ready:
                    process.kill()
                    self.fail("prompt did not appear")
                output += os.read(master, 4096)
            os.write(master, answer)
            code = process.wait(timeout=10)
            return code, output.decode(errors="replace")
        finally:
            os.close(master)
            if slave != -1:
                os.close(slave)

    def test_doctor_missing_and_invalid_are_read_only(self):
        env = self.env.copy()
        env["GATEWAY_SSH_TIMEOUT_SECONDS"] = "invalid"
        result = self.run_cli("doctor", env=env)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("MASALAH: GATEWAY_SSH_TIMEOUT_SECONDS", result.stdout)
        self.assertIn("MASALAH: Direktori", result.stdout)
        self.assertFalse(self.base.exists())
        self.assertEqual(self.run_cli("doctor", "extra").returncode, 2)
        self.assertFalse(self.base.exists())

    def test_doctor_with_existing_directories_and_locked_watcher(self):
        self.prepare()
        before = sorted(str(p.relative_to(self.base)) for p in self.base.rglob("*"))
        with (self.base / "watcher.lock").open("w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            before.append("watcher.lock")
            result = self.run_cli("doctor")
        self.assertIn("OK: Direktori", result.stdout)
        self.assertIn("OK: SSH", result.stdout)
        self.assertIn("Keychain", result.stdout)
        self.assertNotIn("instance gateway lain", result.stdout)
        self.assertEqual(sorted(before), sorted(str(p.relative_to(self.base)) for p in self.base.rglob("*")))

    def test_doctor_inaccessible_directory(self):
        self.prepare()
        directory = self.base / "processing"
        directory.chmod(0)
        try:
            result = self.run_cli("doctor")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("MASALAH: Direktori", result.stdout)
            self.assertIn("processing", result.stdout)
        finally:
            directory.chmod(0o700)

    def test_invalid_clear_does_not_create_directories(self):
        for command in ("clear-responses", "clear-audit"):
            self.assertEqual(self.run_cli(command, "--bad").returncode, 2)
            self.assertFalse(self.base.exists())

    def test_clear_nonterminal_invalid_and_locked(self):
        for command, target in (("clear-responses", "responses/sample.json"), ("clear-audit", "audit.log")):
            with self.subTest(command=command):
                self.prepare()
                for args in ((command,), (command, "--invalid"), (command, "--yes", "extra")):
                    result = self.run_cli(*args)
                    self.assertNotEqual(result.returncode, 0, result.stdout)
                    self.assertTrue((self.base / target).read_text())
                with (self.base / "watcher.lock").open("w") as lock:
                    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    result = self.run_cli(command, "--yes")
                    self.assertNotEqual(result.returncode, 0, result.stdout)
                    self.assertTrue((self.base / target).read_text())

    def test_clear_interactive_and_yes(self):
        for command, target in (("clear-responses", "responses/sample.json"), ("clear-audit", "audit.log")):
            with self.subTest(command=command):
                for answer in (b"n\n", b"\x04"):
                    self.prepare()
                    code, output = self.interactive(command, answer)
                    self.assertNotEqual(code, 0)
                    self.assertIn(str(self.base.name), output)
                    self.assertTrue((self.base / target).read_text())
                for answer in (b"y\n", b"YES\n"):
                    self.prepare()
                    code, _ = self.interactive(command, answer)
                    self.assertEqual(code, 0)
                    self.assertFalse((self.base / target).exists() and (self.base / target).read_text())
                    self.assertEqual((self.base / "responses" / "keep.txt").read_text(), "keep")
                self.prepare()
                result = self.run_cli(command, "--yes")
                self.assertEqual(result.returncode, 0, result.stdout)
                self.assertFalse((self.base / target).exists() and (self.base / target).read_text())


if __name__ == "__main__":
    unittest.main()
