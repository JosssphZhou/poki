#!/usr/bin/env python3
"""Exercise first-time trust through Poki Setup's bridge with a simulated USB iPhone."""
import json
import os
import plistlib
import socketserver
import ssl
import struct
import subprocess
import sys
import tempfile
import threading
from pathlib import Path

UDID = "00008150-0000000000000000"
OTHER_UDID = "00008150-0000000000000001"
RESULT = {"MessageType": "Result"}


class USBConnection(socketserver.StreamRequestHandler):
    def send_mux(self, response, tag):
        body = plistlib.dumps(response)
        self.wfile.write(struct.pack("<4I", len(body) + 16, 1, 8, tag) + body)

    def handle(self):
        while self.rfile.peek(1):
            size, _, _, tag = struct.unpack("<4I", self.rfile.read(16))
            request = plistlib.loads(self.rfile.read(size - 16))
            command = request["MessageType"]
            if command == "ListDevices":
                self.send_mux({"DeviceList": [
                    {"DeviceID": device_id, "Properties": {"ConnectionType": "USB", "SerialNumber": udid}}
                    for device_id, (udid, _) in self.server.phones.items()
                ]}, tag)
            elif command == "ReadBUID":
                self.send_mux({"BUID": "fixture-host"}, tag)
            elif command == "ReadPairRecord":
                record = self.server.system_record
                response = {"PairRecordData": record} if record else dict(RESULT, Number=self.server.record_result)
                self.send_mux(response, tag)
            elif command == "SavePairRecord":
                self.server.system_record = request["PairRecordData"]
                self.send_mux(dict(RESULT, Number=0), tag)
            elif command == "Connect":
                self.send_mux(dict(RESULT, Number=0), tag)
                self.lockdown(self.server.phones[request["DeviceID"]][1])
                return
            else:
                raise ValueError(command)

    def lockdown(self, name):
        while self.rfile.peek(1):
            size, = struct.unpack(">I", self.rfile.read(4))
            request = plistlib.loads(self.rfile.read(size))
            command = request["Request"]
            secure = False
            if command == "GetValue":
                response = {"Value": {
                    None: {"DeviceName": name, "ProductVersion": "26.4"},
                    "DeviceName": name,
                    "ProductVersion": "26.4",
                    "DevicePublicKey": self.server.public_key,
                    "WiFiAddress": "02:00:00:00:00:01",
                    "DeveloperModeStatus": False,
                }[request.get("Key")]}
            elif command == "Pair":
                self.server.pair_requested.set()
                if self.server.accept_trust:
                    self.server.host_id = request["PairRecord"]["HostID"]
                    response = {"Result": "Success"}
                else:
                    response = {"Error": "UserDeniedPairing"}
            elif command == "StartSession":
                secure = request["HostID"] == self.server.host_id
                response = {"EnableSessionSSL": True, "SessionID": "fixture"} if secure else {"Error": "InvalidHostID"}
            else:
                raise ValueError(command)
            body = plistlib.dumps(dict(response, Request=command))
            self.wfile.write(struct.pack(">I", len(body)) + body)
            if secure:
                self.rfile.close()
                self.wfile.close()
                with self.server.tls.wrap_socket(self.request, server_side=True) as connection:
                    self.rfile, self.wfile = connection.makefile("rb"), connection.makefile("wb", buffering=0)
                    try:
                        self.lockdown(name)
                    except ConnectionResetError:
                        return
                return


def call(bridge, command, request_id, udid=UDID):
    bridge.stdin.write(json.dumps({
        "id": request_id, "cmd": command, "args": {"udid": udid},
    }) + "\n")
    bridge.stdin.flush()
    events = []
    for line in bridge.stdout:
        message = json.loads(line)
        if message.get("id") == request_id:
            return message, events
        events.append(message)
    raise AssertionError(f"bridge exited during {command}")


def device_choices_name_the_connected_phones(bridge, mux):
    mux.phones = {1: (UDID, "Fixture iPhone"), 2: (OTHER_UDID, "Fixture iPad")}
    snapshot, _ = call(bridge, "wizard_state", 4, udid=None)
    state = snapshot.get("ok", {})
    assert state.get("state") == "choose_device" and state.get("selected_udid") is None, snapshot
    assert {phone["name"] for phone in state["usb_phones"]} == {"Fixture iPhone", "Fixture iPad"}, snapshot
    print("Two USB devices: both names shown before selecting a target")


def first_connection_requests_trust_before_stopping(bridge, mux):
    snapshot, _ = call(bridge, "wizard_state", 1)
    assert snapshot.get("ok", {}).get("state") == "device_untrusted", snapshot
    result, events = call(bridge, "wizard_pair", 2)
    assert mux.pair_requested.is_set(), f"no Trust request reached the iPhone: {result}"
    assert any(event.get("data", {}).get("kind") == "waiting" for event in events), events
    assert result.get("err", {}).get("kind") == "needs_person", result
    print("No record: device_untrusted → Trust request → needs_person after Don't Trust")

    mux.pair_requested.clear()
    mux.record_result = 22
    failure, _ = call(bridge, "wizard_pair", 3)
    assert "err" in failure and not mux.pair_requested.is_set(), failure
    print("Unexpected record lookup result: stopped before a Trust request")

    mux.record_result = 2
    mux.accept_trust = True
    accepted, _ = call(bridge, "wizard_pair", 5)
    assert accepted.get("ok") is True and mux.system_record, accepted
    snapshot, _ = call(bridge, "wizard_state", 6)
    assert snapshot.get("ok", {}).get("state") == "developer_mode_off", snapshot
    print("After Trust: the record was saved, and the wizard moved to Developer Mode")

    record = plistlib.loads(mux.system_record)
    record["HostID"] = "expired-fixture-host"
    mux.system_record = plistlib.dumps(record)
    snapshot, _ = call(bridge, "wizard_state", 7)
    assert snapshot.get("ok", {}).get("state") == "device_untrusted", snapshot
    mux.pair_requested.clear()
    restored, _ = call(bridge, "wizard_pair", 8)
    assert restored.get("ok") is True and not mux.pair_requested.is_set(), restored
    snapshot, _ = call(bridge, "wizard_state", 9)
    assert snapshot.get("ok", {}).get("state") == "developer_mode_off", snapshot
    print("Stale system record: restored the valid local record and continued without another prompt")


def run(bridge_path, checks):
    with tempfile.TemporaryDirectory(prefix="poki-usb-trust-") as setup_dir, \
            socketserver.ThreadingTCPServer(("127.0.0.1", 0), USBConnection) as mux:
        fixture = Path(setup_dir)
        key = fixture / "fixture.key"
        cert = fixture / "fixture.pem"
        subprocess.run(
            ["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
             "-subj", "/CN=Fixture iPhone", "-keyout", str(key), "-out", str(cert)],
            check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        mux.public_key = subprocess.check_output(
            ["openssl", "rsa", "-in", str(key), "-RSAPublicKey_out"], stderr=subprocess.DEVNULL,
        )
        mux.tls = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        mux.tls.load_cert_chain(cert, key)
        key.unlink()
        cert.unlink()
        mux.pair_requested = threading.Event()
        mux.phones = {1: (UDID, "Fixture iPhone")}
        mux.record_result = 2
        mux.system_record = None
        mux.host_id = None
        mux.accept_trust = False
        server = threading.Thread(target=mux.serve_forever)
        server.start()
        try:
            with subprocess.Popen(
                [bridge_path],
                env=dict(os.environ, POKI_SETUP_HOME=setup_dir, POKI_SETUP_FILE_SECRETS="1",
                         USBMUXD_SOCKET_ADDRESS=f"127.0.0.1:{mux.server_address[1]}"),
                stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True,
            ) as bridge:
                try:
                    for check in checks:
                        check(bridge, mux)
                finally:
                    bridge.stdin.close()
                    bridge.wait(timeout=5)
        finally:
            mux.shutdown()
            server.join()


if __name__ == "__main__":
    checks = [first_connection_requests_trust_before_stopping, device_choices_name_the_connected_phones]
    run(sys.argv[1], checks[1:] if sys.argv[2:] == ["--device-choice-only"] else checks)
