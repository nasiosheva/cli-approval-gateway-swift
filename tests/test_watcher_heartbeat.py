#!/usr/bin/env python3
"""Verify watcher heartbeat with isolated gateway data and a pseudo-terminal."""

import os
from pathlib import Path
import pty
import select
import subprocess
import sys
import tempfile
import time
import unittest


BINARY = str(Path(sys.argv.pop(1)).resolve()) if len(sys.argv) > 1 else "cli-approval-gateway"


class WatcherHeartbeatTest(unittest.TestCase):
    def observe(self, interval, seconds):
        with tempfile.TemporaryDirectory(prefix="gateway-heartbeat-test-") as temp:
            env = {key: value for key, value in os.environ.items() if not key.startswith("GATEWAY_")}
            env.update(GATEWAY_BASE_DIR_NAME=os.path.relpath(Path(temp) / "data", Path.home()),
                       GATEWAY_POLL_INTERVAL_SECONDS="0.1", GATEWAY_IDLE_HEARTBEAT_SECONDS=interval)
            master, slave = pty.openpty()
            proc = subprocess.Popen([BINARY], stdin=slave, stdout=slave, stderr=slave, env=env, close_fds=True)
            os.close(slave)
            output = b""
            try:
                deadline = time.monotonic() + seconds
                while time.monotonic() < deadline:
                    if select.select([master], [], [], min(0.1, max(0, deadline - time.monotonic())))[0]:
                        output += os.read(master, 65536)
                    self.assertIsNone(proc.poll(), output.decode(errors="replace"))
            finally:
                proc.terminate()
                try:
                    proc.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait()
                os.close(master)
            return output.count(b"[idle] menunggu request")

    def test_idle_heartbeat_and_disabled(self):
        count = self.observe("0.5", 2.2)
        self.assertGreaterEqual(count, 2)
        self.assertLessEqual(count, 4)
        self.assertEqual(self.observe("0", 1), 0)


if __name__ == "__main__":
    unittest.main()
