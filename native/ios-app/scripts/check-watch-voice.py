#!/usr/bin/env python3
"""Check that a long Watch task result makes it into history on both paired simulators.

Use a dedicated pair with the Debug apps installed. Give the Watch app microphone access and
leave it on its recording screen on an Ultra (49 mm) simulator. On iPhone, configure the
custom model poki-mock at http://127.0.0.1:<port>/v1. Restart the iPhone app using
simctl launch --terminate-running-process with -pokiWatchVoiceTestTranscript, then turn on
Automation. Pass the built simulator input helper as --helper. Its sibling OCR helper
observes the English Watch interface.
"""

import argparse
from contextlib import closing
from http.server import ThreadingHTTPServer
import json
import os
from pathlib import Path
import runpy
import select
import subprocess
from tempfile import TemporaryDirectory
from threading import Thread
from time import monotonic

PHONE_BUNDLE = "nz.zheha.poki"
WATCH_BUNDLE = PHONE_BUNDLE + ".watchkitapp"
TRANSCRIPT = "Check whether Poki automation is on on this iPhone."
FOOTER = "Final detail: the full answer reached this line. ✅"
LONG_DETAIL = "Read-only verification detail. 漢字 e\u0301 🧪\n" * 650
MockModelHandler = runpy.run_path(str(Path(__file__).with_name("mock-model.py")))["Handler"]


class WatchTaskModel(MockModelHandler):
    """Script the external model. Derive the answer from the real status tool result."""

    def do_POST(self):
        request = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        messages = request["messages"]
        if not any(m["role"] == "user" and TRANSCRIPT in json.dumps(m) for m in messages):
            self.send_error(422, "Expected the Watch transcript")
            return

        tool_results = {m.get("tool_call_id"): m for m in messages if m["role"] == "tool"}
        model = request["model"]
        if "watch-status" not in tool_results:
            self.call(model, "status", {})
            return

        content = self.tool_text(tool_results["watch-status"])
        status = next((line.strip() for line in content.splitlines() if line.startswith("runner:")), None)
        if not status or status == "runner: unknown":
            self.send_error(422, "The task did not return a real runner status")
            return

        if "watch-finish_task" not in tool_results:
            self.call(model, "finish_task", {
                "success": True,
                "summary": "Checked Poki on iPhone.",
                "details": [{"label": "Runner", "value": status.removeprefix("runner: ")}],
                "answer": {"kind": "field"},
            })
            return
        if not self.tool_text(tool_results["watch-finish_task"]).startswith("Result recorded."):
            self.send_error(422, "Poki did not record the task result")
            return

        answer = f"Phone status: {status}\n"
        if self.server.long_result:
            answer += LONG_DETAIL + FOOTER
        self.server.expected_reply = answer.rstrip()
        self.respond(model, {"role": "assistant", "content": self.server.expected_reply}, "stop")

    @staticmethod
    def tool_text(message):
        content = message["content"]
        if isinstance(content, list):
            return "\n".join(part.get("text", "") for part in content if isinstance(part, dict))
        return content

    def call(self, model, name, arguments):
        tool = {"index": 0, "id": f"watch-{name}", "type": "function",
                "function": {"name": name, "arguments": json.dumps(arguments)}}
        self.respond(model, {"role": "assistant", "content": None, "tool_calls": [tool]}, "tool_calls")

    def respond(self, model, message, finish):
        usage = {"prompt_tokens": 100, "completion_tokens": 20, "total_tokens": 120}
        self.stream(model, message, finish, usage)


def archive(device, bundle):
    path = subprocess.check_output(
        ["xcrun", "simctl", "get_app_container", device, bundle, "data"], text=True, timeout=20
    ).strip()
    return Path(path) / "Library" / "Application Support" / "WatchVoice.json"


def results(path):
    try:
        return json.loads(path.read_text())["results"]
    except FileNotFoundError:
        return []


def wait_for_result(path, read, failure):
    path.parent.mkdir(parents=True, exist_ok=True)
    directory = os.open(path.parent, os.O_EVTONLY)
    try:
        with closing(select.kqueue()) as queue:
            change = select.kevent(directory, filter=select.KQ_FILTER_VNODE,
                                   flags=select.KQ_EV_ADD | select.KQ_EV_CLEAR,
                                   fflags=select.KQ_NOTE_WRITE)
            queue.control([change], 0, 0)
            deadline = monotonic() + 30
            while not (result := read()):
                if not queue.control([], 1, max(0, deadline - monotonic())):
                    raise AssertionError(failure)
            return result
    finally:
        os.close(directory)


def touch(session, x, y, hold_ms):
    def event(phase):
        return {"messageType": "IndigoDigitizerEvent", "payload": {
            "pointOne": {"x": x, "y": y}, "eventType": phase, "edge": 0, "target": 0}}

    session.stdin.write(json.dumps({"events": [event(0), {"delay_ms": hold_ms}, event(2)]}) + "\n")
    session.stdin.flush()
    assert json.loads(session.stdout.readline())["sent"], "Simulator input did not send"


def open_result(args, session):
    with TemporaryDirectory() as directory:
        path = Path(directory) / "watch.png"
        subprocess.run(["xcrun", "simctl", "io", args.watch, "screenshot", str(path)],
                       check=True, capture_output=True, timeout=15)
        ocr = Path(args.helper).with_name("ocr")
        screen = json.loads(subprocess.check_output([ocr, path], timeout=15))
        heading = next((line for line in screen if line["text"].endswith("Task finished")), None)
        assert heading, "The Watch did not show the finished result"
        # PNG's IHDR gives the screenshot height in pixels, as used by the OCR bounds.
        height = int.from_bytes(path.read_bytes()[20:24], "big")
        touch(session, 0.48, (heading["y"] + heading["height"] / 2) / height, 75)


def exercise(args, server):
    phone_path = archive(args.phone, PHONE_BUNDLE)
    watch_path = archive(args.watch, WATCH_BUNDLE)
    previous = {entry["id"] for entry in results(watch_path)}

    def latest():
        return next((entry for entry in results(watch_path) if entry["id"] not in previous), None)

    with subprocess.Popen([args.helper, "--hid-session", args.watch], stdin=subprocess.PIPE,
                          stdout=subprocess.PIPE, text=True) as session:
        try:
            assert json.loads(session.stdout.readline())["ready"]
            touch(session, 0.5, 0.38, 1600)
            initial = wait_for_result(watch_path, latest, "No new task result reached the Watch")
            assert server.expected_reply, f"The model did not answer: {initial.get('text', '')[:180]}"

            phone_rows = json.loads(phone_path.read_text())
            phone = dict(zip(phone_rows[::2], phone_rows[1::2]))[initial["id"]]
            expected = server.expected_reply
            assert phone["text"].endswith(expected), (
                f"iPhone saved {len(phone['text'])} characters and lost part of the model's "
                f"{len(expected)}-character reply"
            )

            assert initial["phase"] == 2, f"The task did not finish: {initial.get('text', '')[:180]}"
            open_result(args, session)

            def full_result():
                entry = latest()
                return entry if entry and entry.get("text") == phone["text"] else None

            wait_for_result(watch_path, full_result, "The Watch history never saved the complete reply")
            print(f"Both apps saved the complete successful result ({len(phone['text'])} characters).")
            print(f"Request {initial['id']}. {expected.splitlines()[0]}")
        finally:
            session.stdin.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("phone")
    parser.add_argument("watch")
    parser.add_argument("--helper", required=True)
    parser.add_argument("--port", type=int, default=29152)
    parser.add_argument("--short", action="store_true", help="Use a short result for a screen recording")
    args = parser.parse_args()
    with ThreadingHTTPServer(("127.0.0.1", args.port), WatchTaskModel) as server:
        server.long_result = not args.short
        server.expected_reply = None
        worker = Thread(target=server.serve_forever)
        worker.start()
        try:
            exercise(args, server)
        finally:
            server.shutdown()
            worker.join()


if __name__ == "__main__":
    main()
