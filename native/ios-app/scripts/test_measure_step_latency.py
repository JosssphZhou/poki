#!/usr/bin/env python3
import importlib.util
import json
import plistlib
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

SCRIPT_PATH = Path(__file__).with_name("measure-step-latency.py")
SPEC = importlib.util.spec_from_file_location("measure_step_latency", SCRIPT_PATH)
MOD = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MOD)


class MeasureStepLatencyIsolationTests(unittest.TestCase):
    def test_cli_rejects_external_udid_flag(self):
        proc = subprocess.run(
            [
                sys.executable,
                str(SCRIPT_PATH),
                "--udid", "EXISTING-SIM-UDID",
                "--target", "fix=abc=/tmp/Poki.app",
                "--out", "/tmp/out",
            ],
            text=True,
            capture_output=True,
            timeout=10,
        )
        self.assertEqual(proc.returncode, 2, proc.stderr)
        self.assertIn("unrecognized arguments: --udid", proc.stderr)

    def test_run_one_refuses_unowned_simulator_without_modifying_container(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            app = root / "Poki.app"
            app.mkdir()
            (app / "Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": "nz.zheha.poki"}))

            container = root / "container"
            mem_file = container / "Library/Application Support/Poki/agent-memory.json"
            mem_file.parent.mkdir(parents=True)
            original_mem = json.dumps({"schema": "poki.agent-memory/2", "notes": [{"id": "keep-me"}]})
            mem_file.write_text(original_mem)

            session_file = container / "Library/Application Support/Poki/Sessions/s1.json"
            session_file.parent.mkdir(parents=True)
            session_file.write_text('{"id":"s1"}')

            backup_file = container / "Documents/AgentBackup/b1.json"
            backup_file.parent.mkdir(parents=True)
            backup_file.write_text('{"id":"b1"}')

            def fake_sim(*args, **kwargs):
                if args and args[0] == "get_app_container":
                    return str(container) + "\n"
                return ""

            dummy_server = mock.MagicMock()
            dummy_server.server_port = 12345

            with mock.patch.object(MOD, "sim", side_effect=fake_sim):
                with self.assertRaises(ValueError):
                    MOD.run_one(
                        dummy_server,
                        "EXTERNAL-SIM-UDID",
                        app,
                        "label",
                        "sha",
                        "web",
                        "empty",
                        0,
                        root / "out",
                        developer_dir="/Applications/Xcode.app/Contents/Developer",
                    )

            self.assertEqual(mem_file.read_text(), original_mem)
            self.assertTrue(session_file.exists())
            self.assertTrue(backup_file.exists())

    def test_ephemeral_simulator_creates_boots_and_deletes_on_failure(self):
        calls = []

        def fake_sim(*args, **kwargs):
            calls.append(args)
            if args[0] == "create":
                return "NEW-TEMP-UDID\n"
            return ""

        with mock.patch.object(MOD, "sim", side_effect=fake_sim):
            with self.assertRaises(RuntimeError):
                with MOD.ephemeral_simulator(
                    device_type="com.apple.CoreSimulator.SimDeviceType.iPhone-17",
                    runtime="com.apple.CoreSimulator.SimRuntime.iOS-27-2",
                ) as udid:
                    self.assertEqual(udid, "NEW-TEMP-UDID")
                    self.assertIn(udid, MOD.OWNED_SIMULATORS)
                    raise RuntimeError("boom")

        self.assertNotIn("NEW-TEMP-UDID", MOD.OWNED_SIMULATORS)
        verbs = [c[0] for c in calls]
        self.assertEqual(verbs, ["create", "boot", "bootstatus", "shutdown", "delete"])
        self.assertEqual(calls[-1][1], "NEW-TEMP-UDID")

    def test_unknown_memory_profile_raises_value_error(self):
        with self.assertRaises(ValueError):
            MOD.make_memory_file("phone_shape")


if __name__ == "__main__":
    unittest.main()
