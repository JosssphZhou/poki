#!/usr/bin/env python3
"""Compare Poki voice speed and correctness across baseline and candidate builds.

Runs paired, alternating baseline/candidate voice trials (via simulator silent
rehearsal or the shared voice-bridge recorded-audio replay entry point), keeps
every failure, timeout, and boundary sample, and renders a Markdown comparison
report. A candidate is judged `speedup` only when the final target is
independently confirmed, verified task success rate does not drop, safety
counters do not regress, and primary latency improves beyond run-to-run spread.
"""

from __future__ import annotations

import argparse
import atexit
from contextlib import contextmanager
from dataclasses import asdict, dataclass, is_dataclass
from datetime import datetime, timezone
import json
import math
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import time
from typing import Any
from urllib.parse import quote

SCHEMA_VERSION = "poki.voice-speed-compare/1"
SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_SAMPLES_PATH = SCRIPT_DIR / "voice-compare" / "samples.json"
DEFAULT_TEMPLATE_PATH = SCRIPT_DIR / "voice-compare" / "report-template.md"

VOICE_HOSTS = ("phone_direct", "voice_bridge")
ACTION_HOSTS = ("phone_local", "mac_tools")
SCENARIO_GROUPS = ("cold_start", "warm_session", "visual_evidence", "mid_turn_revision")
UTTERANCE_CLASSES = ("short_command", "long_paused_utterance")
EDGE_FLAGS = ("animation_enabled", "target_unchanged", "no_new_frame")
CHECKLIST_CATEGORIES = (
    "stop",
    "duplicate_utterance",
    "disconnect_reconnect",
    "tool_failure",
    "continuation",
    "permission_denied",
)
PRIMARY_METRICS = (
    "target_confirmed_ms",
    "action_to_confirmed_ms",
    "first_effective_action_ms",
    "spoken_ms",
)
ALL_MILESTONE_METRICS = (
    "said_ms",
    "heard_ms",
    "call_ms",
    "first_effective_action_ms",
    "tool_done_ms",
    "target_confirmed_ms",
    "action_to_confirmed_ms",
    "delivered_ms",
    "spoken_ms",
    "phone_local_ms",
    "mac_tools_ms",
    "mac_tools_roundtrip_ms",
    "wall_ms",
)
READ_ONLY_TOOLS = frozenset({"get_ios_version", "look", "read_screen", "cancel_current_task"})
PLACEHOLDER_CONFIG_VALUES = frozenset({"", "none", "unknown"})
MIN_NOISE_FLOOR_MS = 10.0

FAILURE_REPLY_PATTERNS = (
    re.compile(
        r"\b(fail(?:ed|ure)?|error|unable|cannot|can't|couldn't|could not|denied|declined|refused|"
        r"cancel(?:led|ed)?|stopped|timed?\s*out|blocked|unconfirmed|not\s+confirmed|unknown|lost|"
        r"disconnect(?:ed)?)\b",
        re.I,
    ),
    re.compile(
        r"(失败|无法|没能|不能|未能|未完成|未确认|拒绝|已取消|已停止|超时|断连|断开|连接中断|出错|错误|被拦|未发送)"
    ),
)
LOG_LINE_RE = re.compile(r"^(\d{2}):(\d{2}):(\d{2})\.(\d{3})\s+\[([^\]]+)\]\s+(.*)$")
LEGACY_TURN_RE = re.compile(
    r"turn:\s+end of speech to spoken result\s+(\d+)\s+ms\s+\(tool result in\s+(\d+)\s+ms"
)
TOOL_START_RE = re.compile(r"^tool\s+([A-Za-z0-9_]+)\s+(\{.*\}|\[.*\])$")
TOOL_END_RE = re.compile(r"^tool\s+([A-Za-z0-9_]+)\s+(done|failed)\s+\|")
REDACTED_TYPED_RE = re.compile(r'"type"\s*:\s*"…"')
KV_TOKEN_RE = re.compile(r"([A-Za-z0-9_]+)=([^\s]+)")

OWNED_SIMULATORS: set[str] = set()


def _cleanup_owned_simulators() -> None:
    for udid in list(OWNED_SIMULATORS):
        OWNED_SIMULATORS.discard(udid)
        try:
            subprocess.run(["xcrun", "simctl", "shutdown", udid], capture_output=True, timeout=15)
            subprocess.run(["xcrun", "simctl", "delete", udid], capture_output=True, timeout=30)
        except Exception:
            pass


atexit.register(_cleanup_owned_simulators)


@dataclass(frozen=True)
class BuildTarget:
    side: str
    label: str
    commit: str
    app_path: Path


@dataclass(frozen=True)
class MetricStats:
    count: int
    p50: float | None
    p95: float | None
    min_val: float | None
    max_val: float | None
    iqr: float | None


def _json_default(obj: Any) -> Any:
    if is_dataclass(obj) and not isinstance(obj, type):
        return asdict(obj)
    if isinstance(obj, Path):
        return str(obj)
    raise TypeError(f"Object of type {type(obj).__name__} is not JSON serializable")


def dumps_json(obj: Any, *, indent: int | None = 2) -> str:
    return json.dumps(obj, ensure_ascii=False, indent=indent, default=_json_default)


def parse_target_spec(raw: str, side: str) -> BuildTarget:
    parts = raw.split("=", 2)
    if len(parts) != 3 or not all(p.strip() for p in parts):
        raise ValueError(f"invalid --{side} value {raw!r}; expected label=commit=/path/to/Poki.app")
    label, commit, path_str = (p.strip() for p in parts)
    return BuildTarget(side=side, label=label, commit=commit, app_path=Path(path_str))


def load_samples_manifest(path: Path) -> dict[str, Any]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict) or not isinstance(data.get("samples"), list):
        raise ValueError(f"invalid sample manifest at {path}")
    return data


def validate_samples_manifest(manifest: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    samples = manifest.get("samples")
    if not isinstance(samples, list) or not samples:
        return ["samples list is missing or empty"]

    seen_ids: set[str] = set()
    seen_indices: set[int] = set()
    seen_hosts: set[str] = set()
    seen_groups: dict[str, set[str]] = {h: set() for h in VOICE_HOSTS}
    seen_classes: dict[str, set[str]] = {h: set() for h in VOICE_HOSTS}
    seen_edges: set[str] = set()
    seen_checklist: set[str] = set()
    rehearsal_count = 0

    for idx, sample in enumerate(samples):
        sid = sample.get("id")
        if not isinstance(sid, str) or not sid.strip():
            errors.append(f"sample[{idx}] missing non-empty id")
            continue
        if sid in seen_ids:
            errors.append(f"duplicate sample id {sid!r}")
        seen_ids.add(sid)

        u_idx = sample.get("utterance_index")
        if not isinstance(u_idx, int) or u_idx < 1 or u_idx > 99:
            errors.append(f"{sid}: utterance_index must be an integer in 1..99")
        elif u_idx in seen_indices:
            errors.append(f"{sid}: duplicate utterance_index {u_idx}")
        else:
            seen_indices.add(u_idx)

        audio_file = sample.get("audio_file")
        expected_audio = f"u{u_idx:02d}.24k.pcm" if isinstance(u_idx, int) else None
        if expected_audio and audio_file != expected_audio:
            errors.append(f"{sid}: audio_file {audio_file!r} does not match {expected_audio!r}")

        host = sample.get("voice_host")
        if host not in VOICE_HOSTS:
            errors.append(f"{sid}: invalid voice_host {host!r}")
        else:
            seen_hosts.add(host)

        expected_action_host = sample.get("expected_action_host")
        if expected_action_host not in ACTION_HOSTS:
            errors.append(f"{sid}: invalid expected_action_host {expected_action_host!r}")
        elif host == "phone_direct" and expected_action_host == "mac_tools":
            errors.append(f"{sid}: phone_direct sample must not set expected_action_host='mac_tools'")

        group = sample.get("group")
        if group not in SCENARIO_GROUPS:
            errors.append(f"{sid}: invalid group {group!r}")
        elif host in seen_groups:
            seen_groups[host].add(group)

        u_class = sample.get("utterance_class")
        if u_class not in UTTERANCE_CLASSES:
            errors.append(f"{sid}: invalid utterance_class {u_class!r}")
        elif host in seen_classes:
            seen_classes[host].add(u_class)

        edges = sample.get("edge_flags") or []
        if not isinstance(edges, list):
            errors.append(f"{sid}: edge_flags must be a list")
        else:
            for flag in edges:
                if flag not in EDGE_FLAGS:
                    errors.append(f"{sid}: unknown edge_flag {flag!r}")
                else:
                    seen_edges.add(flag)

        cat = sample.get("checklist_category")
        if cat in CHECKLIST_CATEGORIES:
            seen_checklist.add(cat)
        elif cat != "core_speed":
            errors.append(f"{sid}: invalid checklist_category {cat!r}")

        modes = sample.get("entry_modes") or []
        if "rehearsal" in modes:
            rehearsal_count += 1
            if sample.get("rehearsal_variant") not in ("1", "lost"):
                errors.append(f"{sid}: rehearsal sample must set rehearsal_variant to '1' or 'lost'")

    for host in VOICE_HOSTS:
        if host not in seen_hosts:
            errors.append(f"manifest missing voice_host {host!r}")
        missing_groups = sorted(set(SCENARIO_GROUPS) - seen_groups.get(host, set()))
        if missing_groups:
            errors.append(f"manifest missing groups for {host}: {', '.join(missing_groups)}")
        missing_classes = sorted(set(UTTERANCE_CLASSES) - seen_classes.get(host, set()))
        if missing_classes:
            errors.append(f"manifest missing utterance_classes for {host}: {', '.join(missing_classes)}")

    missing_edges = sorted(set(EDGE_FLAGS) - seen_edges)
    if missing_edges:
        errors.append(f"manifest missing edge_flags: {', '.join(missing_edges)}")
    missing_checklist = sorted(set(CHECKLIST_CATEGORIES) - seen_checklist)
    if missing_checklist:
        errors.append(f"manifest missing checklist_categories: {', '.join(missing_checklist)}")
    if rehearsal_count == 0:
        errors.append("manifest must contain at least one simulator rehearsal sample")
    return errors


def percentile(values: list[float], p: float) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    if len(ordered) == 1:
        return float(ordered[0])
    idx = p * (len(ordered) - 1)
    lo = math.floor(idx)
    hi = math.ceil(idx)
    if lo == hi:
        return float(ordered[lo])
    return float(ordered[lo] + (idx - lo) * (ordered[hi] - ordered[lo]))


def compute_metric_stats(values: list[float | int | None]) -> MetricStats:
    clean = sorted(float(v) for v in values if v is not None)
    if not clean:
        return MetricStats(count=0, p50=None, p95=None, min_val=None, max_val=None, iqr=None)
    q25 = percentile(clean, 0.25)
    q75 = percentile(clean, 0.75)
    iqr = (q75 - q25) if (q25 is not None and q75 is not None) else None
    return MetricStats(
        count=len(clean),
        p50=percentile(clean, 0.50),
        p95=percentile(clean, 0.95),
        min_val=clean[0],
        max_val=clean[-1],
        iqr=iqr,
    )


def build_alternating_schedule(samples: list[dict[str, Any]], rounds: int) -> list[tuple[int, int, str, dict[str, Any]]]:
    schedule: list[tuple[int, int, str, dict[str, Any]]] = []
    order_index = 0
    for round_num in range(1, rounds + 1):
        sides = ("baseline", "candidate") if round_num % 2 == 1 else ("candidate", "baseline")
        for sample in samples:
            for side in sides:
                schedule.append((round_num, order_index, side, sample))
                order_index += 1
    return schedule


def _parse_int_or_none(raw: Any) -> int | None:
    if raw is None:
        return None
    text = str(raw).strip()
    if not text or text.lower() == "none":
        return None
    try:
        return int(text)
    except ValueError:
        return None


def _wall_clock_ms(h: str, m: str, s: str, ms: str) -> int:
    return ((int(h) * 3600 + int(m) * 60 + int(s)) * 1000) + int(ms)


def _wall_delta_ms(start_ms: int | None, end_ms: int | None) -> int | None:
    if start_ms is None or end_ms is None:
        return None
    delta = end_ms - start_ms
    if delta < -43_200_000:
        delta += 86_400_000
    return max(0, delta)


def _normalize_host_ms(
    action_host: str,
    phone_local: int | None,
    mac_tools: int | None,
    mac_rt: int | None,
) -> dict[str, int | None]:
    has_phone = action_host in ("phone_local", "mixed") or (phone_local is not None and phone_local > 0)
    has_mac = (
        action_host in ("mac_tools", "mixed")
        or (mac_tools is not None and mac_tools > 0)
        or (mac_rt is not None and mac_rt > 0)
    )
    return {
        "phone_local_ms": phone_local if has_phone else None,
        "mac_tools_ms": mac_tools if has_mac else None,
        "mac_tools_roundtrip_ms": mac_rt if has_mac else None,
    }


def reply_reports_failure(reply: str) -> bool:
    trimmed = reply.strip()
    if not trimmed:
        return True
    return any(pattern.search(trimmed) for pattern in FAILURE_REPLY_PATTERNS)


def _count_duplicate_write_calls(tool_starts: list[tuple[int, str, str]]) -> int:
    seen: set[tuple[str, str]] = set()
    duplicates = 0
    for _, name, raw_args in tool_starts:
        if name in READ_ONLY_TOOLS:
            continue
        args = raw_args.strip()
        if REDACTED_TYPED_RE.search(args):
            continue
        key = (name, args)
        if key in seen:
            duplicates += 1
        else:
            seen.add(key)
    return duplicates


def parse_poki_log(
    log_text: str,
    *,
    entry_mode: str,
    sample: dict[str, Any],
    timed_out: bool = False,
) -> dict[str, Any]:
    timing_events: list[dict[str, Any]] = []
    legacy_turn: tuple[int, int] | None = None
    speech_stopped_times: list[int] = []
    tool_starts: list[tuple[int, str, str]] = []
    tool_ends: list[tuple[int, str, bool, bool]] = []
    connection_errors: list[str] = []
    screen_delivery_failures: list[str] = []
    reply_started_after_tool = False
    saw_tool_done = False

    for line in log_text.splitlines():
        match = LOG_LINE_RE.match(line.strip())
        if not match:
            continue
        t_wall = _wall_clock_ms(*match.groups()[:4])
        area = match.group(5)
        msg = match.group(6)

        if area == "voice-timing":
            kv = dict(KV_TOKEN_RE.findall(msg))
            kv["_wall_ms"] = t_wall
            timing_events.append(kv)
        elif area == "voice":
            m_end = TOOL_END_RE.match(msg)
            if m_end:
                is_control = "| control:" in msg
                tool_ends.append((t_wall, m_end.group(1), m_end.group(2) == "done", is_control))
                saw_tool_done = True
                if "desc=failed(" in msg or "image=failed(" in msg:
                    screen_delivery_failures.append(msg)
                continue
            m_start = TOOL_START_RE.match(msg)
            if m_start:
                tool_starts.append((t_wall, m_start.group(1), m_start.group(2)))
                continue
            if "model speech stopped" in msg:
                speech_stopped_times.append(t_wall)
            elif (
                "connection lost:" in msg
                or "could not connect:" in msg
                or "the server said nothing" in msg
                or "realtime error:" in msg
            ):
                connection_errors.append(msg)
            elif "screenshot not sent" in msg or "desc=failed(" in msg or "image=failed(" in msg:
                screen_delivery_failures.append(msg)
            m_turn = LEGACY_TURN_RE.search(msg)
            if m_turn and legacy_turn is None:
                legacy_turn = (int(m_turn.group(1)), int(m_turn.group(2)))
            if "reply playback started" in msg and saw_tool_done:
                reply_started_after_tool = True

    milestones: dict[str, int | None] = {
        "said_ms": None,
        "heard_ms": None,
        "call_ms": None,
        "first_effective_action_ms": None,
        "tool_done_ms": None,
        "target_confirmed_ms": None,
        "delivered_ms": None,
        "spoken_ms": None,
    }
    host_ms: dict[str, int | None] = {
        "phone_local_ms": None,
        "mac_tools_ms": None,
        "mac_tools_roundtrip_ms": None,
    }
    entry_route = "rehearsal" if entry_mode == "rehearsal" else "none"
    voice_host = sample.get("voice_host", "phone_direct")
    action_host = "none"
    observation_source = "none"
    model_name = "rehearsal" if entry_mode == "rehearsal" else "unknown"
    transport = "rehearsal" if entry_mode == "rehearsal" else "unknown"
    tool_calls: list[str] = []
    timing_source = "none"
    had_tool_failure = False
    duplicate_inputs = 0
    premature_truncation = False
    model_roundtrips = 0

    if timing_events:
        timing_source = "voice-timing"
        entry_ev = next((ev for ev in timing_events if ev.get("event") == "entry_selected"), None)
        if entry_ev:
            entry_route = entry_ev.get("entry_route", entry_route)
            voice_host = entry_ev.get("voice_host", voice_host)
            model_name = entry_ev.get("model", model_name)
            transport = entry_ev.get("transport", transport)

        spoken_events = [ev for ev in timing_events if ev.get("event") == "turn_spoken"]
        primary_turn: int | None = None
        if spoken_events:
            primary_turn = _parse_int_or_none(spoken_events[0].get("turn"))
        else:
            action_turns = [
                _parse_int_or_none(ev.get("turn"))
                for ev in timing_events
                if ev.get("event") in ("action_start", "turn_said")
            ]
            action_turns = [t for t in action_turns if t is not None and t > 0]
            if action_turns:
                primary_turn = action_turns[0]

        turn_events = [
            ev for ev in timing_events
            if primary_turn is None or _parse_int_or_none(ev.get("turn")) == primary_turn
        ]
        spoken_ev = next((ev for ev in turn_events if ev.get("event") == "turn_spoken"), None)
        if spoken_ev:
            entry_route = spoken_ev.get("entry_route", entry_route)
            voice_host = spoken_ev.get("voice_host", voice_host)
            action_host = spoken_ev.get("action_host", action_host)
            observation_source = spoken_ev.get("observation_source", observation_source)
            for key in milestones:
                milestones[key] = _parse_int_or_none(spoken_ev.get(key))
            host_ms = _normalize_host_ms(
                action_host,
                _parse_int_or_none(spoken_ev.get("phone_local_ms")),
                _parse_int_or_none(spoken_ev.get("mac_tools_ms")),
                _parse_int_or_none(spoken_ev.get("mac_tools_roundtrip_ms")),
            )
            raw_calls = spoken_ev.get("calls", "none")
            if raw_calls and raw_calls != "none":
                tool_calls = [c for c in raw_calls.split(",") if c]
        else:
            raw_phone = 0
            raw_mac = 0
            raw_mac_rt = 0
            for ev in turn_events:
                ev_type = ev.get("event")
                if ev_type == "turn_said":
                    milestones["said_ms"] = 0
                elif ev_type == "turn_heard" and milestones["heard_ms"] is None:
                    milestones["heard_ms"] = _parse_int_or_none(ev.get("since_said_ms"))
                elif ev_type == "action_start":
                    if milestones["call_ms"] is None:
                        milestones["call_ms"] = _parse_int_or_none(ev.get("since_said_ms"))
                    tool_name = ev.get("tool")
                    if tool_name:
                        tool_calls.append(tool_name)
                elif ev_type == "first_effective_action" and milestones["first_effective_action_ms"] is None:
                    milestones["first_effective_action_ms"] = _parse_int_or_none(ev.get("since_said_ms"))
                elif ev_type == "action_end":
                    milestones["tool_done_ms"] = _parse_int_or_none(ev.get("since_said_ms"))
                    if ev.get("effective") == "true":
                        milestones["target_confirmed_ms"] = None
                    ah = ev.get("action_host", "none")
                    if ah != "none":
                        action_host = ah if action_host in ("none", ah) else "mixed"
                    obs = ev.get("observation_source", "none")
                    if obs != "none":
                        observation_source = obs
                    tms = _parse_int_or_none(ev.get("tool_ms"))
                    tms_val = tms if tms is not None else 0
                    if ah == "phone_local":
                        raw_phone += tms_val
                    elif ah == "mac_tools":
                        b_ms = _parse_int_or_none(ev.get("bridge_ms"))
                        rt_ms = _parse_int_or_none(ev.get("roundtrip_ms"))
                        raw_mac += b_ms if b_ms is not None else tms_val
                        raw_mac_rt += rt_ms if rt_ms is not None else tms_val
                elif ev_type == "target_confirmed" and milestones["target_confirmed_ms"] is None:
                    milestones["target_confirmed_ms"] = _parse_int_or_none(ev.get("since_said_ms"))
                elif ev_type == "result_delivered":
                    milestones["delivered_ms"] = _parse_int_or_none(ev.get("since_said_ms"))
            host_ms = _normalize_host_ms(action_host, raw_phone, raw_mac, raw_mac_rt)

        had_tool_failure = any(
            ev.get("event") == "action_end" and ev.get("ok") == "false"
            for ev in turn_events
        )

        next_turn_wall: int | None = None
        if primary_turn is not None:
            later_turns = [
                ev["_wall_ms"]
                for ev in timing_events
                if ev.get("event") == "turn_said"
                and (_parse_int_or_none(ev.get("turn")) or 0) > primary_turn
            ]
            if later_turns:
                next_turn_wall = later_turns[0]
        turn_tool_starts = [
            ts for ts in tool_starts if next_turn_wall is None or ts[0] < next_turn_wall
        ]
        duplicate_inputs = _count_duplicate_write_calls(turn_tool_starts)

        said_count = sum(1 for ev in timing_events if ev.get("event") == "turn_said")
        if entry_mode != "rehearsal" and sample.get("utterance_class") == "long_paused_utterance" and said_count > 1:
            premature_truncation = True

        action_starts = sum(1 for ev in turn_events if ev.get("event") == "action_start")
        model_roundtrips = action_starts + (1 if milestones["spoken_ms"] is not None else 0)
    elif legacy_turn is not None or tool_starts or speech_stopped_times:
        timing_source = "legacy-voice-log"
        if legacy_turn is not None:
            milestones["said_ms"] = 0
            milestones["spoken_ms"] = legacy_turn[0]
            milestones["delivered_ms"] = legacy_turn[1]
        said_wall = speech_stopped_times[0] if speech_stopped_times else None
        next_said_wall = speech_stopped_times[1] if len(speech_stopped_times) > 1 else None
        turn_starts = [
            ts for ts in tool_starts
            if (said_wall is None or ts[0] >= said_wall) and (next_said_wall is None or ts[0] < next_said_wall)
        ]
        turn_ends = [
            te for te in tool_ends
            if not te[3]
            and (said_wall is None or te[0] >= said_wall)
            and (next_said_wall is None or te[0] < next_said_wall)
        ]
        had_tool_failure = any(not ok for _, _, ok, _ in turn_ends)
        if turn_starts:
            tool_calls = [name for _, name, _ in turn_starts]
            if said_wall is not None:
                milestones["call_ms"] = _wall_delta_ms(said_wall, turn_starts[0][0])
        if turn_ends:
            if said_wall is not None:
                milestones["tool_done_ms"] = _wall_delta_ms(said_wall, turn_ends[-1][0])
            action_host = sample.get("expected_action_host", "phone_local")
            if len(turn_starts) == len(turn_ends):
                total_tool_ms = sum(_wall_delta_ms(s[0], e[0]) or 0 for s, e in zip(turn_starts, turn_ends))
                if action_host == "mac_tools":
                    host_ms = _normalize_host_ms(action_host, None, total_tool_ms, total_tool_ms)
                else:
                    host_ms = _normalize_host_ms(action_host, total_tool_ms, None, None)
        duplicate_inputs = _count_duplicate_write_calls(turn_starts)
        if entry_mode != "rehearsal" and sample.get("utterance_class") == "long_paused_utterance" and len(speech_stopped_times) > 1:
            premature_truncation = True
        model_roundtrips = len(tool_calls) + (1 if (milestones["spoken_ms"] is not None or reply_started_after_tool) else 0)

    target_confirmed = milestones["target_confirmed_ms"] is not None
    action_to_confirmed_ms = None
    if milestones["first_effective_action_ms"] is not None and milestones["target_confirmed_ms"] is not None:
        action_to_confirmed_ms = max(0, milestones["target_confirmed_ms"] - milestones["first_effective_action_ms"])

    errors: list[str] = []
    if timed_out:
        errors.append("timeout waiting for voice turn completion")
    errors.extend(connection_errors)
    if had_tool_failure:
        errors.append("one or more voice tools failed")
    if screen_delivery_failures:
        errors.append("; ".join(screen_delivery_failures))
    if not timed_out and milestones["spoken_ms"] is None and not errors:
        errors.append("no completed voice turn observed in app log")

    status = "timeout" if timed_out else ("failed" if errors else "ok")
    false_completion_announced = False
    verified_success = (
        status == "ok"
        and not timed_out
        and target_confirmed
        and not false_completion_announced
    )

    return {
        "entry_route": entry_route,
        "voice_host": voice_host,
        "action_host": action_host,
        "observation_source": observation_source,
        "status": status,
        "timeout": timed_out,
        "error": "; ".join(errors),
        "target_confirmed": target_confirmed,
        "verified_success": verified_success,
        "premature_truncation": premature_truncation,
        "duplicate_inputs": duplicate_inputs,
        "false_completion_announced": false_completion_announced,
        "model_roundtrips": model_roundtrips,
        "tool_calls": tool_calls,
        "milestones_ms": milestones,
        "derived_ms": {"action_to_confirmed_ms": action_to_confirmed_ms},
        "host_ms": host_ms,
        "timing_source": timing_source,
        "config_fingerprint": {
            "model": model_name,
            "transport": transport,
            "vad": "rehearsal_script" if entry_mode == "rehearsal" else "bridge_or_direct",
            "locale": sample.get("locale", "en"),
        },
    }


def record_from_bridge_report(
    report: dict[str, Any],
    *,
    side: str,
    build_label: str,
    commit_sha: str,
    changed_variable: str,
    round_num: int,
    order_index: int,
    sample: dict[str, Any],
    environment: dict[str, Any] | None = None,
    config_fingerprint: dict[str, Any] | None = None,
    log_parsed: dict[str, Any] | None = None,
    wall_ms: int | None = None,
) -> dict[str, Any]:
    ms_raw = report.get("ms") if isinstance(report.get("ms"), dict) else {}
    milestones = {
        "said_ms": _parse_int_or_none(ms_raw.get("said")),
        "heard_ms": _parse_int_or_none(ms_raw.get("heard")),
        "call_ms": _parse_int_or_none(ms_raw.get("call")),
        "first_effective_action_ms": _parse_int_or_none(ms_raw.get("first_effective_action")),
        "tool_done_ms": _parse_int_or_none(ms_raw.get("toolDone")),
        "target_confirmed_ms": _parse_int_or_none(ms_raw.get("target_confirmed")),
        "delivered_ms": _parse_int_or_none(ms_raw.get("delivered")),
        "spoken_ms": _parse_int_or_none(ms_raw.get("spoken")),
    }
    if log_parsed:
        for k, v in log_parsed["milestones_ms"].items():
            if milestones[k] is None and v is not None:
                milestones[k] = v

    action_to_confirmed_ms = None
    if milestones["first_effective_action_ms"] is not None and milestones["target_confirmed_ms"] is not None:
        action_to_confirmed_ms = max(0, milestones["target_confirmed_ms"] - milestones["first_effective_action_ms"])

    action_host = str(report.get("action_host") or (log_parsed["action_host"] if log_parsed else "none"))
    entry_route = str(report.get("entry_route") or (log_parsed["entry_route"] if log_parsed else "none"))
    voice_host = str(report.get("voice_host") or (log_parsed["voice_host"] if log_parsed else sample["voice_host"]))
    observation_source = str(
        report.get("observation_source") or (log_parsed["observation_source"] if log_parsed else "none")
    )

    if isinstance(report.get("host_ms"), dict):
        raw_host_ms = report["host_ms"]
        host_ms = _normalize_host_ms(
            action_host,
            _parse_int_or_none(raw_host_ms.get("phone_local")),
            _parse_int_or_none(raw_host_ms.get("mac_tools")),
            _parse_int_or_none(raw_host_ms.get("mac_tools_roundtrip")),
        )
    elif log_parsed:
        host_ms = dict(log_parsed["host_ms"])
    else:
        host_ms = {"phone_local_ms": None, "mac_tools_ms": None, "mac_tools_roundtrip_ms": None}

    calls = list(report.get("calls") or [])
    reply = str(report.get("reply") or "")
    ok_flag = bool(report.get("ok"))
    raw_error = str(report.get("error") or "").strip()
    timed_out = (
        bool(report.get("timeout"))
        or "timeout" in raw_error.lower()
        or (not ok_flag and not raw_error and milestones["spoken_ms"] is None)
    )
    if timed_out and not raw_error:
        raw_error = "timeout waiting for spoken turn completion"

    target_confirmed = milestones["target_confirmed_ms"] is not None
    has_confirmation_telemetry = (
        "observation_source" in report
        or "entry_route" in report
        or "target_confirmed" in ms_raw
        or (log_parsed is not None and log_parsed.get("timing_source") == "voice-timing")
    )
    false_completion_announced = bool(report.get("false_completion_announced"))
    if (
        not false_completion_announced
        and milestones["spoken_ms"] is not None
        and not target_confirmed
        and reply
        and not reply_reports_failure(reply)
    ):
        if has_confirmation_telemetry or not ok_flag or bool(raw_error):
            false_completion_announced = True

    duplicate_inputs = int(report.get("duplicate_inputs") or 0)
    if log_parsed:
        duplicate_inputs = max(duplicate_inputs, int(log_parsed.get("duplicate_inputs") or 0))

    premature_truncation = bool(report.get("premature_truncation")) or bool(
        log_parsed and log_parsed.get("premature_truncation")
    )
    model_roundtrips = int(
        report.get("model_roundtrips")
        or (log_parsed.get("model_roundtrips") if log_parsed else 0)
        or (len(calls) + (1 if milestones["spoken_ms"] is not None else 0))
    )
    status = "timeout" if timed_out else ("ok" if ok_flag and not raw_error else "failed")
    verified_success = (
        status == "ok"
        and not timed_out
        and target_confirmed
        and not false_completion_announced
    )

    if config_fingerprint is not None:
        fp = dict(config_fingerprint)
    else:
        fp = {
            "entry_route": entry_route if entry_route != "none" else "unknown",
            "locale": sample.get("locale", "en"),
        }

    return {
        "schema": SCHEMA_VERSION,
        "run_id": f"r{round_num:02d}_{order_index:03d}_{side}_{sample['id']}",
        "round": round_num,
        "order_index": order_index,
        "side": side,
        "build_label": build_label,
        "commit_sha": commit_sha,
        "changed_variable": changed_variable,
        "entry_mode": "bridge_replay",
        "sample_id": sample["id"],
        "utterance_index": sample["utterance_index"],
        "voice_host": voice_host,
        "action_host": action_host,
        "entry_route": entry_route,
        "observation_source": observation_source,
        "group": sample["group"],
        "utterance_class": sample["utterance_class"],
        "checklist_category": sample["checklist_category"],
        "edge_flags": list(sample.get("edge_flags") or []),
        "locale": sample.get("locale", "en"),
        "environment": environment or {"surface": "bridge_replay"},
        "config_fingerprint": fp,
        "status": status,
        "timeout": timed_out,
        "error": raw_error,
        "target_confirmed": target_confirmed,
        "verified_success": verified_success,
        "premature_truncation": premature_truncation,
        "duplicate_inputs": duplicate_inputs,
        "false_completion_announced": false_completion_announced,
        "model_roundtrips": model_roundtrips,
        "tool_calls": calls,
        "milestones_ms": milestones,
        "derived_ms": {
            "action_to_confirmed_ms": action_to_confirmed_ms,
            "wall_ms": wall_ms,
        },
        "host_ms": host_ms,
        "timing_source": "voice-test-report",
        "notes": "",
    }


def extract_metric_value(record: dict[str, Any], metric: str) -> float | None:
    milestones = record.get("milestones_ms") or {}
    derived = record.get("derived_ms") or {}
    host_ms = record.get("host_ms") or {}
    if metric in milestones:
        val = milestones[metric]
        return float(val) if val is not None else None
    if metric in derived:
        val = derived[metric]
        return float(val) if val is not None else None
    if metric in host_ms:
        val = host_ms[metric]
        return float(val) if val is not None else None
    if metric == "action_to_confirmed_ms":
        first = milestones.get("first_effective_action_ms")
        confirmed = milestones.get("target_confirmed_ms")
        if first is not None and confirmed is not None:
            return float(max(0, confirmed - first))
    return None


def _is_verified_record(record: dict[str, Any]) -> bool:
    return (
        record.get("status") == "ok"
        and not bool(record.get("timeout"))
        and bool(record.get("target_confirmed"))
        and not bool(record.get("false_completion_announced"))
    )


def summarize_records(records: list[dict[str, Any]], primary_metric: str) -> dict[str, Any]:
    total = len(records)
    completed = [r for r in records if r.get("status") == "ok" and not r.get("timeout")]
    confirmed = [r for r in records if bool(r.get("target_confirmed"))]
    verified = [r for r in records if _is_verified_record(r)]
    failed = [r for r in records if r.get("status") == "failed"]
    timeouts = [r for r in records if bool(r.get("timeout")) or r.get("status") == "timeout"]
    truncations = [r for r in records if bool(r.get("premature_truncation"))]
    dup_total = sum(int(r.get("duplicate_inputs") or 0) for r in records)
    false_comp_total = sum(1 for r in records if bool(r.get("false_completion_announced")))
    roundtrips_vals = [int(r.get("model_roundtrips") or 0) for r in records]
    roundtrip_stats = compute_metric_stats(roundtrips_vals)

    verified_primary_vals = [extract_metric_value(r, primary_metric) for r in verified]
    all_primary_vals = [extract_metric_value(r, primary_metric) for r in records]
    primary_verified_stats = compute_metric_stats(verified_primary_vals)
    primary_all_stats = compute_metric_stats(all_primary_vals)

    milestones_stats = {
        m: compute_metric_stats([extract_metric_value(r, m) for r in records])
        for m in ALL_MILESTONE_METRICS
    }

    return {
        "total": total,
        "completed_count": len(completed),
        "completed_rate": (len(completed) / total) if total else None,
        "confirmed_count": len(confirmed),
        "confirmed_rate": (len(confirmed) / total) if total else None,
        "verified_success_count": len(verified),
        "task_success_rate": (len(verified) / total) if total else None,
        "failed_count": len(failed),
        "timeout_count": len(timeouts),
        "premature_truncation_count": len(truncations),
        "premature_truncation_rate": (len(truncations) / total) if total else None,
        "duplicate_input_count": dup_total,
        "false_completion_announcements": false_comp_total,
        "model_roundtrips_total": sum(roundtrips_vals),
        "model_roundtrips": roundtrip_stats,
        "primary_verified": primary_verified_stats,
        "primary_all": primary_all_stats,
        "milestones": milestones_stats,
    }


def _count_by_sample(records: list[dict[str, Any]]) -> dict[str, int]:
    counts: dict[str, int] = {}
    for r in records:
        sid = str(r.get("sample_id") or "")
        counts[sid] = counts.get(sid, 0) + 1
    return counts


def _is_interleaved(records: list[dict[str, Any]]) -> bool:
    rounds_by_side: dict[str, set[int]] = {"baseline": set(), "candidate": set()}
    orders_by_side: dict[str, list[int]] = {"baseline": [], "candidate": []}
    for r in records:
        side = r.get("side")
        rnd = r.get("round")
        if side in rounds_by_side and isinstance(rnd, int):
            rounds_by_side[side].add(rnd)
            orders_by_side[side].append(int(r.get("order_index", 0)))
    shared_rounds = rounds_by_side["baseline"] & rounds_by_side["candidate"]
    if not shared_rounds:
        return False
    if len(shared_rounds) == 1:
        return True
    if max(orders_by_side["baseline"]) < min(orders_by_side["candidate"]) or max(orders_by_side["candidate"]) < min(orders_by_side["baseline"]):
        return False
    first_side_per_round: list[str] = []
    for rnd in sorted(shared_rounds):
        round_rows = sorted(
            (r for r in records if r.get("round") == rnd),
            key=lambda x: int(x.get("order_index", 0)),
        )
        if round_rows:
            first_side_per_round.append(str(round_rows[0].get("side")))
    return len(set(first_side_per_round)) >= 2


def _is_placeholder_config(value: Any) -> bool:
    if value is None:
        return True
    if isinstance(value, str) and value.strip().lower() in PLACEHOLDER_CONFIG_VALUES:
        return True
    return False


def _check_config_drift(
    baseline: list[dict[str, Any]],
    candidate: list[dict[str, Any]],
    allow_diff: set[str],
) -> list[str]:
    def collect(rows: list[dict[str, Any]]) -> dict[tuple[str, str], set[str]]:
        out: dict[tuple[str, str], set[str]] = {}
        for r in rows:
            sid = str(r.get("sample_id") or "")
            fp = r.get("config_fingerprint") or {}
            for k, v in fp.items():
                if k in allow_diff or _is_placeholder_config(v):
                    continue
                out.setdefault((sid, k), set()).add(json.dumps(v, sort_keys=True, ensure_ascii=False))
        return out

    b_fp = collect(baseline)
    c_fp = collect(candidate)
    drifts: list[str] = []
    for sid, key in sorted(set(b_fp) & set(c_fp)):
        if b_fp[(sid, key)] != c_fp[(sid, key)]:
            drifts.append(
                f"{sid}.{key}: baseline={sorted(b_fp[(sid, key)])} vs candidate={sorted(c_fp[(sid, key)])}"
            )
    return drifts


def _check_host_attribution(host: str, records: list[dict[str, Any]]) -> list[str]:
    violations: list[str] = []
    if host == "phone_direct":
        for r in records:
            ah = r.get("action_host")
            mac_ms = int((r.get("host_ms") or {}).get("mac_tools_ms") or 0)
            mac_rt = int((r.get("host_ms") or {}).get("mac_tools_roundtrip_ms") or 0)
            if ah == "mac_tools" or mac_ms > 0 or mac_rt > 0:
                violations.append(
                    f"{r.get('run_id')}: phone_direct record attributed action_host={ah} mac_tools_ms={mac_ms}"
                )
    return violations


def _within_sample_noise_floor(
    baseline: list[dict[str, Any]],
    candidate: list[dict[str, Any]],
    primary_metric: str,
) -> float:
    spreads: list[float] = []
    for rows in (baseline, candidate):
        by_sample: dict[str, list[float]] = {}
        for r in rows:
            if not _is_verified_record(r):
                continue
            val = extract_metric_value(r, primary_metric)
            if val is not None:
                by_sample.setdefault(str(r.get("sample_id") or ""), []).append(val)
        for vals in by_sample.values():
            stats = compute_metric_stats(vals)
            if stats.count >= 4 and stats.iqr is not None and stats.iqr > 0:
                spreads.append(stats.iqr)
            elif stats.count >= 2 and stats.max_val is not None and stats.min_val is not None:
                spreads.append(stats.max_val - stats.min_val)
    return max([MIN_NOISE_FLOOR_MS, *spreads])


def judge_host_comparison(
    host: str,
    records: list[dict[str, Any]],
    *,
    primary_metric: str,
    min_rounds: int,
    allow_config_diff: set[str],
) -> dict[str, Any]:
    baseline = [r for r in records if r.get("side") == "baseline"]
    candidate = [r for r in records if r.get("side") == "candidate"]
    b_sum = summarize_records(baseline, primary_metric)
    c_sum = summarize_records(candidate, primary_metric)

    reasons: list[str] = []
    regressed = False
    inconclusive = False
    no_diff = False

    if host not in VOICE_HOSTS:
        inconclusive = True
        reasons.append(f"unrecognized_voice_host: {host!r} is not one of {', '.join(VOICE_HOSTS)}")

    if not baseline or not candidate:
        reasons.append("missing_baseline_or_candidate: need paired runs for both baseline and candidate")
        return {
            "host": host,
            "verdict": "not_faster",
            "verdict_detail": "inconclusive",
            "reasons": reasons,
            "baseline": b_sum,
            "candidate": c_sum,
            "noise_floor_ms": None,
            "delta_p50_ms": None,
            "delta_p50_pct": None,
            "delta_p95_ms": None,
            "interleaved": False,
            "config_drifts": [],
            "attribution_violations": [],
        }

    b_counts = _count_by_sample(baseline)
    c_counts = _count_by_sample(candidate)
    if b_counts != c_counts:
        inconclusive = True
        reasons.append(f"unmatched_sample_set: baseline={b_counts} candidate={c_counts}")

    changed_vars = {str(r.get("changed_variable") or "").strip() for r in records} - {""}
    if len(changed_vars) != 1:
        inconclusive = True
        reasons.append(f"single_variable_missing_or_ambiguous: {sorted(changed_vars)}")

    interleaved = _is_interleaved(records)
    if not interleaved:
        inconclusive = True
        reasons.append("not_interleaved: baseline and candidate were not alternated across rounds")

    drifts = _check_config_drift(baseline, candidate, allow_config_diff)
    if drifts:
        inconclusive = True
        reasons.append("config_drift: " + "; ".join(drifts))

    attribution_violations = _check_host_attribution(host, records)
    if attribution_violations:
        inconclusive = True
        reasons.append("host_attribution_violation: " + "; ".join(attribution_violations[:3]))

    min_per_sample = min(min(b_counts.values()), min(c_counts.values()))
    if min_per_sample < min_rounds:
        inconclusive = True
        reasons.append(f"insufficient_rounds: min runs per sample is {min_per_sample} < required {min_rounds}")

    if b_sum["confirmed_count"] == 0 or c_sum["confirmed_count"] == 0:
        inconclusive = True
        reasons.append(
            f"target_not_independently_confirmed: baseline confirmed={b_sum['confirmed_count']}/{b_sum['total']}, "
            f"candidate confirmed={c_sum['confirmed_count']}/{c_sum['total']}"
        )

    b_sr = b_sum["task_success_rate"] or 0.0
    c_sr = c_sum["task_success_rate"] or 0.0
    if c_sr < b_sr:
        regressed = True
        reasons.append(
            f"success_rate_regressed: candidate {c_sr * 100:.1f}% ({c_sum['verified_success_count']}/{c_sum['total']}) "
            f"< baseline {b_sr * 100:.1f}% ({b_sum['verified_success_count']}/{b_sum['total']})"
        )
    elif b_sum["confirmed_count"] == 0 and c_sum["confirmed_count"] == 0:
        b_comp = b_sum["completed_rate"] or 0.0
        c_comp = c_sum["completed_rate"] or 0.0
        if c_comp < b_comp:
            regressed = True
            reasons.append(
                f"completion_rate_regressed: candidate {c_comp * 100:.1f}% ({c_sum['completed_count']}/{c_sum['total']}) "
                f"< baseline {b_comp * 100:.1f}% ({b_sum['completed_count']}/{b_sum['total']})"
            )

    if c_sum["false_completion_announcements"] > b_sum["false_completion_announcements"]:
        regressed = True
        reasons.append(
            f"false_completion_regressed: candidate {c_sum['false_completion_announcements']} "
            f"> baseline {b_sum['false_completion_announcements']}"
        )
    if c_sum["duplicate_input_count"] > b_sum["duplicate_input_count"]:
        regressed = True
        reasons.append(
            f"duplicate_input_regressed: candidate {c_sum['duplicate_input_count']} "
            f"> baseline {b_sum['duplicate_input_count']}"
        )
    b_trunc = b_sum["premature_truncation_rate"] or 0.0
    c_trunc = c_sum["premature_truncation_rate"] or 0.0
    if c_trunc > b_trunc:
        regressed = True
        reasons.append(
            f"premature_truncation_regressed: candidate {c_trunc * 100:.1f}% > baseline {b_trunc * 100:.1f}%"
        )

    b_lat = b_sum["primary_verified"]
    c_lat = c_sum["primary_verified"]
    delta_p50_ms = None
    delta_p50_pct = None
    delta_p95_ms = None
    noise_floor_ms = None

    if b_lat.p50 is None or c_lat.p50 is None:
        inconclusive = True
        reasons.append(
            f"missing_primary_latency: {primary_metric} has baseline n={b_lat.count}, candidate n={c_lat.count} on verified runs"
        )
    else:
        b_ver_by_sample = _count_by_sample([r for r in baseline if _is_verified_record(r)])
        c_ver_by_sample = _count_by_sample([r for r in candidate if _is_verified_record(r)])
        has_sufficient_verified_sample = any(
            b_ver_by_sample.get(sid, 0) >= min_rounds and c_ver_by_sample.get(sid, 0) >= min_rounds
            for sid in b_counts
        )
        if b_lat.count < min_rounds or c_lat.count < min_rounds or not has_sufficient_verified_sample:
            inconclusive = True
            reasons.append(
                f"insufficient_verified_runs: verified primary count baseline={b_lat.count}, "
                f"candidate={c_lat.count} (need at least {min_rounds} verified runs per sample)"
            )

        delta_p50_ms = c_lat.p50 - b_lat.p50
        delta_p50_pct = ((delta_p50_ms / b_lat.p50) * 100.0) if b_lat.p50 > 0 else None
        if b_lat.p95 is not None and c_lat.p95 is not None:
            delta_p95_ms = c_lat.p95 - b_lat.p95

        noise_floor_ms = _within_sample_noise_floor(baseline, candidate, primary_metric)

        if delta_p50_ms >= 0:
            if delta_p50_ms > noise_floor_ms:
                regressed = True
                reasons.append(
                    f"latency_regressed: candidate P50 {c_lat.p50:.1f} ms > baseline P50 {b_lat.p50:.1f} ms (+{delta_p50_ms:.1f} ms)"
                )
            elif delta_p95_ms is not None and delta_p95_ms > noise_floor_ms:
                regressed = True
                reasons.append(
                    f"tail_latency_regressed: candidate P95 {c_lat.p95:.1f} ms > baseline P95 {b_lat.p95:.1f} ms (+{delta_p95_ms:.1f} ms)"
                )
            else:
                no_diff = True
                reasons.append(
                    f"latency_not_improved: candidate P50 {c_lat.p50:.1f} ms vs baseline {b_lat.p50:.1f} ms ({delta_p50_ms:+.1f} ms)"
                )
        else:
            improvement = -delta_p50_ms
            if delta_p95_ms is not None and delta_p95_ms > 0:
                regressed = True
                reasons.append(
                    f"tail_latency_regressed: candidate P95 {c_lat.p95:.1f} ms > baseline P95 {b_lat.p95:.1f} ms (+{delta_p95_ms:.1f} ms)"
                )
            if improvement <= noise_floor_ms:
                no_diff = True
                reasons.append(
                    f"within_noise_floor: P50 improvement {improvement:.1f} ms <= run-to-run variation {noise_floor_ms:.1f} ms"
                )

    if not reasons:
        verdict = "speedup"
        detail = "speedup"
        pct_part = f", {delta_p50_pct:+.1f}%" if delta_p50_pct is not None else ""
        reasons.append(
            f"verified_speedup: {primary_metric} P50 {b_lat.p50:.1f} ms -> {c_lat.p50:.1f} ms "
            f"({delta_p50_ms:+.1f} ms{pct_part}), P95 {_fmt_ms(b_lat.p95)} ms -> {_fmt_ms(c_lat.p95)} ms, "
            f"exceeding variation {noise_floor_ms:.1f} ms with non-regressing verified success rate "
            f"({b_sr * 100:.1f}% -> {c_sr * 100:.1f}%)"
        )
    else:
        verdict = "not_faster"
        if regressed:
            detail = "regressed"
        elif inconclusive:
            detail = "inconclusive"
        elif no_diff:
            detail = "no_measurable_difference"
        else:
            detail = "inconclusive"

    return {
        "host": host,
        "verdict": verdict,
        "verdict_detail": detail,
        "reasons": reasons,
        "baseline": b_sum,
        "candidate": c_sum,
        "noise_floor_ms": noise_floor_ms,
        "delta_p50_ms": delta_p50_ms,
        "delta_p50_pct": delta_p50_pct,
        "delta_p95_ms": delta_p95_ms,
        "interleaved": interleaved,
        "config_drifts": drifts,
        "attribution_violations": attribution_violations,
    }


def evaluate_comparison(
    records: list[dict[str, Any]],
    *,
    primary_metric: str = "target_confirmed_ms",
    min_rounds: int = 5,
    allow_config_diff: set[str] | None = None,
) -> dict[str, Any]:
    allow_diff = allow_config_diff or set()
    by_host: dict[str, list[dict[str, Any]]] = {h: [] for h in VOICE_HOSTS}
    for r in records:
        host = str(r.get("voice_host") or "none")
        by_host.setdefault(host, []).append(r)

    eval_hosts = list(VOICE_HOSTS) + sorted(h for h in by_host if h not in VOICE_HOSTS)
    host_results: dict[str, dict[str, Any]] = {}
    measured_hosts: list[str] = []
    for host in eval_hosts:
        rows = by_host.get(host, [])
        if rows:
            measured_hosts.append(host)
        host_results[host] = judge_host_comparison(
            host,
            rows,
            primary_metric=primary_metric,
            min_rounds=min_rounds,
            allow_config_diff=allow_diff,
        )

    if not measured_hosts:
        overall_verdict = "not_faster"
        overall_detail = "inconclusive"
        overall_reasons = ["no_records: input dataset contains zero measurements"]
    else:
        measured_evals = [host_results[h] for h in measured_hosts]
        if all(e["verdict"] == "speedup" for e in measured_evals):
            overall_verdict = "speedup"
            overall_detail = "speedup"
        elif any(e["verdict_detail"] == "regressed" for e in measured_evals):
            overall_verdict = "not_faster"
            overall_detail = "regressed"
        elif any(e["verdict_detail"] == "inconclusive" for e in measured_evals):
            overall_verdict = "not_faster"
            overall_detail = "inconclusive"
        else:
            overall_verdict = "not_faster"
            overall_detail = "no_measurable_difference"
        overall_reasons = [
            f"[{h}] {reason}" for h in measured_hosts for reason in host_results[h]["reasons"]
        ]

    return {
        "schema": SCHEMA_VERSION,
        "primary_metric": primary_metric,
        "min_rounds": min_rounds,
        "overall_verdict": overall_verdict,
        "overall_detail": overall_detail,
        "overall_reasons": overall_reasons,
        "measured_hosts": measured_hosts,
        "hosts": host_results,
        "total_records": len(records),
    }


def _fmt_ms(val: float | None) -> str:
    return f"{val:.1f}" if val is not None else "n/a"


def _fmt_stat_cell(stats: MetricStats) -> str:
    if stats.count == 0 or stats.p50 is None:
        return "n/a (not measured)"
    return f"P50 {stats.p50:.1f} / P95 {stats.p95:.1f} [{stats.min_val:.1f}..{stats.max_val:.1f}] (n={stats.count})"


def _fmt_pct(val: float | None) -> str:
    return f"{val * 100:.1f}%" if val is not None else "n/a"


def _fmt_delta(b_val: float | None, c_val: float | None) -> str:
    if b_val is None or c_val is None:
        return "n/a (not measured)"
    diff = c_val - b_val
    if b_val > 0:
        pct = (diff / b_val) * 100.0
        return f"{diff:+.1f} ms ({pct:+.1f}%)"
    return f"{diff:+.1f} ms"


def _render_slice_table(
    records: list[dict[str, Any]],
    *,
    hosts: list[str],
    slice_field: str,
    slice_values: tuple[str, ...],
    primary_metric: str,
) -> str:
    lines = [
        "| Voice Host | Slice | Side | Runs | Verified Success | Confirmed | Premature Trunc. | Dup Inputs | False Comp. | Roundtrips (P50/P95) | Primary P50 / P95 (ms) | Spoken P50 / P95 (ms) |",
        "| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- | --- |",
    ]
    for host in hosts:
        host_rows = [r for r in records if str(r.get("voice_host") or "none") == host]
        for val in slice_values:
            bucket = [r for r in host_rows if r.get(slice_field) == val]
            if not bucket:
                lines.append(
                    f"| `{host}` | `{val}` | baseline / candidate | 0 | n/a | n/a | n/a | 0 | 0 | n/a | n/a (not measured) | n/a (not measured) |"
                )
                continue
            for side in ("baseline", "candidate"):
                s_rows = [r for r in bucket if r.get("side") == side]
                s = summarize_records(s_rows, primary_metric)
                rt = (
                    f"{s['model_roundtrips'].p50:.1f} / {s['model_roundtrips'].p95:.1f}"
                    if s["model_roundtrips"].count
                    else "n/a"
                )
                prim = s["primary_verified"] if s["primary_verified"].count else s["primary_all"]
                prim_tag = "" if s["primary_verified"].count else " [unconfirmed]"
                prim_txt = (
                    f"{prim.p50:.1f} / {prim.p95:.1f}{prim_tag}" if prim.count and prim.p50 is not None else "n/a (not measured)"
                )
                sp = s["milestones"]["spoken_ms"]
                sp_txt = f"{sp.p50:.1f} / {sp.p95:.1f}" if sp.count and sp.p50 is not None else "n/a (not measured)"
                lines.append(
                    f"| `{host}` | `{val}` | {side} | {s['total']} | "
                    f"{_fmt_pct(s['task_success_rate'])} ({s['verified_success_count']}/{s['total']}) | "
                    f"{_fmt_pct(s['confirmed_rate'])} ({s['confirmed_count']}/{s['total']}) | "
                    f"{_fmt_pct(s['premature_truncation_rate'])} | "
                    f"{s['duplicate_input_count']} | {s['false_completion_announcements']} | "
                    f"{rt} | {prim_txt} | {sp_txt} |"
                )
    return "\n".join(lines)


def render_report(
    records: list[dict[str, Any]],
    evaluation: dict[str, Any],
    *,
    template_path: Path = DEFAULT_TEMPLATE_PATH,
    limiter_note: str = "",
    replay_note: str = "",
) -> str:
    template = template_path.read_text(encoding="utf-8")
    primary_metric = evaluation["primary_metric"]
    eval_hosts = list(evaluation["hosts"].keys())

    overall_label = (
        "**SPEEDUP**"
        if evaluation["overall_verdict"] == "speedup"
        else f"**NOT FASTER ({evaluation['overall_detail']})**"
    )
    decision_lines = "\n".join(f"  - {reason}" for reason in evaluation["overall_reasons"])

    baseline_rows = [r for r in records if r.get("side") == "baseline"]
    candidate_rows = [r for r in records if r.get("side") == "candidate"]

    def build_desc(rows: list[dict[str, Any]]) -> str:
        if not rows:
            return "n/a (0 runs)"
        labels = sorted({str(r.get("build_label") or r.get("side")) for r in rows})
        commits = sorted({str(r.get("commit_sha") or "unknown") for r in rows})
        return f"`{'/'.join(labels)}` @ `{','.join(commits)}`"

    changed_vars = sorted({str(r.get("changed_variable") or "unspecified") for r in records})
    entry_modes = sorted({str(r.get("entry_mode") or "unknown") for r in records})

    if not replay_note:
        if "rehearsal" in entry_modes and "bridge_replay" not in entry_modes:
            replay_note = (
                "Silent simulator rehearsal (`-pokiTalk talk -pokiTalkRehearsal 1|lost`) used while "
                "recorded-audio replay fixtures (`-pokiVoiceLink` + `bin/voice-bridge.mjs --test-dir`) "
                "are pending. Sample IDs and `uNN.24k.pcm` indices share the same replay manifest."
            )
        else:
            replay_note = (
                "Shared voice-bridge recorded-audio replay entry (`-pokiVoiceLink` + "
                "`bin/voice-bridge.mjs --test-dir`)."
            )

    envs = [r.get("environment") or {} for r in records if isinstance(r.get("environment"), dict)]
    surfaces = sorted({str(e.get("surface") or "unknown") for e in envs})
    devices = sorted({str(e.get("device_model") or "") for e in envs if e.get("device_model")})
    oses = sorted({str(e.get("os_version") or "") for e in envs if e.get("os_version")})
    xcodes = sorted({str(e.get("xcode_build") or "") for e in envs if e.get("xcode_build")})
    cpus = sorted({str(e.get("cpu_count")) for e in envs if e.get("cpu_count") is not None})
    loads = [float(e["load_avg_1m"]) for e in envs if e.get("load_avg_1m") is not None]
    env_parts = [f"surface={','.join(surfaces) or 'unknown'}"]
    if devices:
        env_parts.append(f"device={','.join(devices)}")
    if oses:
        env_parts.append(f"os={','.join(oses)}")
    if xcodes:
        env_parts.append(f"xcode={','.join(xcodes)}")
    if cpus:
        env_parts.append(f"cpus={','.join(cpus)}")
    if loads:
        env_parts.append(f"host_load_1m={min(loads):.2f}..{max(loads):.2f}")
    env_summary = "; ".join(env_parts)

    rounds_seen = sorted({int(r["round"]) for r in records if isinstance(r.get("round"), int)})
    interleaved_all = bool(evaluation["measured_hosts"]) and all(
        evaluation["hosts"][h]["interleaved"] for h in evaluation["measured_hosts"]
    )
    interleaving_summary = (
        f"Alternating across {len(rounds_seen)} rounds ({rounds_seen[0]}..{rounds_seen[-1]}), interleaved={interleaved_all}"
        if rounds_seen else "n/a"
    )

    all_drifts = [d for h in eval_hosts for d in evaluation["hosts"][h]["config_drifts"]]
    config_drift_summary = "PASS (no unintended config drift)" if not all_drifts else "DRIFT DETECTED: " + "; ".join(all_drifts)

    total_failed = sum(1 for r in records if r.get("status") == "failed")
    total_timeouts = sum(1 for r in records if bool(r.get("timeout")) or r.get("status") == "timeout")
    total_runs_summary = (
        f"{len(records)} total (baseline={len(baseline_rows)}, candidate={len(candidate_rows)}, "
        f"failed={total_failed}, timeout={total_timeouts}; 0 dropped)"
    )

    per_host_blocks: list[str] = []
    for host in eval_hosts:
        h_eval = evaluation["hosts"][host]
        b = h_eval["baseline"]
        c = h_eval["candidate"]
        if b["total"] == 0 and c["total"] == 0:
            per_host_blocks.append(f"### Host: `{host}`\n\n0 runs collected (not measured in this run; pending recorded-audio replay or device execution).\n")
            continue
        verdict_txt = (
            "SPEEDUP" if h_eval["verdict"] == "speedup" else f"NOT FASTER ({h_eval['verdict_detail']})"
        )
        block = [
            f"### Host: `{host}` -> **{verdict_txt}**",
            "",
            "| Metric | Baseline | Candidate | Delta (Candidate - Baseline) |",
            "| --- | --- | --- | --- |",
            f"| Runs (retained) | {b['total']} (failed={b['failed_count']}, timeout={b['timeout_count']}) | {c['total']} (failed={c['failed_count']}, timeout={c['timeout_count']}) | {c['total'] - b['total']:+d} |",
            f"| Verified task success rate | {_fmt_pct(b['task_success_rate'])} ({b['verified_success_count']}/{b['total']}) | {_fmt_pct(c['task_success_rate'])} ({c['verified_success_count']}/{c['total']}) | {((c['task_success_rate'] or 0) - (b['task_success_rate'] or 0)) * 100:+.1f} pp |",
            f"| Independent target confirmation | {_fmt_pct(b['confirmed_rate'])} ({b['confirmed_count']}/{b['total']}) | {_fmt_pct(c['confirmed_rate'])} ({c['confirmed_count']}/{c['total']}) | {((c['confirmed_rate'] or 0) - (b['confirmed_rate'] or 0)) * 100:+.1f} pp |",
            f"| Raw completion rate (status=ok) | {_fmt_pct(b['completed_rate'])} ({b['completed_count']}/{b['total']}) | {_fmt_pct(c['completed_rate'])} ({c['completed_count']}/{c['total']}) | {((c['completed_rate'] or 0) - (b['completed_rate'] or 0)) * 100:+.1f} pp |",
            f"| Premature truncation rate | {_fmt_pct(b['premature_truncation_rate'])} ({b['premature_truncation_count']}/{b['total']}) | {_fmt_pct(c['premature_truncation_rate'])} ({c['premature_truncation_count']}/{c['total']}) | {((c['premature_truncation_rate'] or 0) - (b['premature_truncation_rate'] or 0)) * 100:+.1f} pp |",
            f"| Duplicate input count | {b['duplicate_input_count']} | {c['duplicate_input_count']} | {c['duplicate_input_count'] - b['duplicate_input_count']:+d} |",
            f"| False completion announcements | {b['false_completion_announcements']} | {c['false_completion_announcements']} | {c['false_completion_announcements'] - b['false_completion_announcements']:+d} |",
            f"| Model roundtrips (P50 / P95 / total) | {_fmt_ms(b['model_roundtrips'].p50)} / {_fmt_ms(b['model_roundtrips'].p95)} / {b['model_roundtrips_total']} | {_fmt_ms(c['model_roundtrips'].p50)} / {_fmt_ms(c['model_roundtrips'].p95)} / {c['model_roundtrips_total']} | {c['model_roundtrips_total'] - b['model_roundtrips_total']:+d} total |",
            f"| Primary `{primary_metric}` (verified runs) | {_fmt_stat_cell(b['primary_verified'])} | {_fmt_stat_cell(c['primary_verified'])} | {_fmt_delta(b['primary_verified'].p50, c['primary_verified'].p50)} |",
            f"| `spoken_ms` (all completed turns) | {_fmt_stat_cell(b['milestones']['spoken_ms'])} | {_fmt_stat_cell(c['milestones']['spoken_ms'])} | {_fmt_delta(b['milestones']['spoken_ms'].p50, c['milestones']['spoken_ms'].p50)} |",
            f"| Run-to-run variation floor (`noise_floor_ms`) | n/a | n/a | {_fmt_ms(h_eval['noise_floor_ms'])} ms |",
            "",
            "Reasons:",
            *[f"- {r}" for r in h_eval["reasons"]],
            "",
        ]
        per_host_blocks.append("\n".join(block))

    milestone_lines = [
        "| Voice Host | Milestone | Baseline (ms) | Candidate (ms) | P50 Delta |",
        "| --- | --- | --- | --- | --- |",
    ]
    for host in eval_hosts:
        h_eval = evaluation["hosts"][host]
        if h_eval["baseline"]["total"] == 0 and h_eval["candidate"]["total"] == 0:
            continue
        for m in ALL_MILESTONE_METRICS:
            bs = h_eval["baseline"]["milestones"][m]
            cs = h_eval["candidate"]["milestones"][m]
            milestone_lines.append(
                f"| `{host}` | `{m}` | {_fmt_stat_cell(bs)} | {_fmt_stat_cell(cs)} | {_fmt_delta(bs.p50, cs.p50)} |"
            )

    attr_counts: dict[tuple[str, str, str, str, str], int] = {}
    for r in records:
        key = (
            str(r.get("side") or ""),
            str(r.get("entry_route") or "none"),
            str(r.get("voice_host") or "none"),
            str(r.get("action_host") or "none"),
            str(r.get("observation_source") or "none"),
        )
        attr_counts[key] = attr_counts.get(key, 0) + 1
    attr_lines = [
        "| Side | Entry Route | Voice Host | Action Host | Observation Source | Runs |",
        "| --- | --- | --- | --- | --- | ---: |",
    ]
    for (side, route, vh, ah, obs), cnt in sorted(attr_counts.items()):
        attr_lines.append(f"| {side} | `{route}` | `{vh}` | `{ah}` | `{obs}` | {cnt} |")

    group_table = _render_slice_table(
        records, hosts=eval_hosts, slice_field="group", slice_values=SCENARIO_GROUPS, primary_metric=primary_metric
    )
    utterance_table = _render_slice_table(
        records, hosts=eval_hosts, slice_field="utterance_class", slice_values=UTTERANCE_CLASSES, primary_metric=primary_metric
    )

    edge_lines = [
        "| Voice Host | Category / Edge Flag | Baseline Runs Retained | Candidate Runs Retained | Verified Success (B / C) | Failed or Timeout (B / C) |",
        "| --- | --- | ---: | ---: | --- | --- |",
    ]
    edge_hosts = evaluation["measured_hosts"] or list(VOICE_HOSTS)
    for host in edge_hosts:
        b_host = [r for r in baseline_rows if str(r.get("voice_host") or "none") == host]
        c_host = [r for r in candidate_rows if str(r.get("voice_host") or "none") == host]
        for flag in EDGE_FLAGS:
            b_e = [r for r in b_host if flag in (r.get("edge_flags") or [])]
            c_e = [r for r in c_host if flag in (r.get("edge_flags") or [])]
            bs = summarize_records(b_e, primary_metric)
            cs = summarize_records(c_e, primary_metric)
            edge_lines.append(
                f"| `{host}` | edge:`{flag}` | {bs['total']} | {cs['total']} | "
                f"{bs['verified_success_count']}/{bs['total']} vs {cs['verified_success_count']}/{cs['total']} | "
                f"{bs['failed_count'] + bs['timeout_count']} vs {cs['failed_count'] + cs['timeout_count']} |"
            )
        for cat in (*CHECKLIST_CATEGORIES, "core_speed"):
            b_c = [r for r in b_host if r.get("checklist_category") == cat]
            c_c = [r for r in c_host if r.get("checklist_category") == cat]
            bs = summarize_records(b_c, primary_metric)
            cs = summarize_records(c_c, primary_metric)
            edge_lines.append(
                f"| `{host}` | checklist:`{cat}` | {bs['total']} | {cs['total']} | "
                f"{bs['verified_success_count']}/{bs['total']} vs {cs['verified_success_count']}/{cs['total']} | "
                f"{bs['failed_count'] + bs['timeout_count']} vs {cs['failed_count'] + cs['timeout_count']} |"
            )

    violation_rows = [
        r for r in records
        if r.get("status") != "ok"
        or bool(r.get("timeout"))
        or bool(r.get("error"))
        or bool(r.get("false_completion_announced"))
        or int(r.get("duplicate_inputs") or 0) > 0
        or bool(r.get("premature_truncation"))
    ]
    if not violation_rows:
        failures_table = "None (0 failures, 0 timeouts, 0 guardrail violations)."
    else:
        f_lines = [
            "| Run ID | Side | Round | Sample | Voice Host | Group | Status | Timeout | Target Confirmed | False Comp. | Dup Inputs | Premature Trunc. | Error |",
            "| --- | --- | ---: | --- | --- | --- | --- | --- | --- | --- | ---: | --- | --- |",
        ]
        for r in violation_rows:
            err = str(r.get("error") or "").replace("|", "/").replace("\n", " ")
            f_lines.append(
                f"| `{r.get('run_id')}` | {r.get('side')} | {r.get('round')} | `{r.get('sample_id')}` | "
                f"`{r.get('voice_host')}` | `{r.get('group')}` | `{r.get('status')}` | "
                f"{str(bool(r.get('timeout'))).lower()} | {str(bool(r.get('target_confirmed'))).lower()} | "
                f"{str(bool(r.get('false_completion_announced'))).lower()} | {int(r.get('duplicate_inputs') or 0)} | "
                f"{str(bool(r.get('premature_truncation'))).lower()} | {err} |"
            )
        failures_table = "\n".join(f_lines)

    notes_parts = []
    if limiter_note:
        notes_parts.append(f"- **Limiter:** {limiter_note}")
    else:
        notes_parts.append("- **Limiter:** Not separately profiled in this report; see per-milestone breakdown and host load average above.")
    if "rehearsal" in entry_modes:
        notes_parts.append(
            "- **Simulator rehearsal scope:** `-pokiTalk talk -pokiTalkRehearsal 1|lost` uses a fixed 3.2 s synthetic tool wait "
            "returning `\"done\"` without live model TTFT, real microphone audio, or independent screen readback. "
            "It verifies the comparison harness, log parsing, host attribution, failure retention, and absence of regression, "
            "and is NOT verified on a physical iPhone."
        )
    notes_parts.append(
        "- **Verification surface:** Not verified on a physical iPhone unless `surface=physical_iphone` is shown in Run Metadata."
    )

    replacements = {
        "{{OVERALL_VERDICT}}": overall_label,
        "{{PRIMARY_METRIC}}": primary_metric,
        "{{DECISION_REASONS}}": decision_lines,
        "{{GENERATED_AT}}": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "{{BASELINE_DESC}}": build_desc(baseline_rows),
        "{{CANDIDATE_DESC}}": build_desc(candidate_rows),
        "{{CHANGED_VARIABLE}}": ", ".join(changed_vars) if changed_vars else "unspecified",
        "{{ENTRY_MODE}}": ", ".join(entry_modes) if entry_modes else "unknown",
        "{{REPLAY_NOTE}}": replay_note,
        "{{INTERLEAVING_SUMMARY}}": interleaving_summary,
        "{{ENVIRONMENT_SUMMARY}}": env_summary,
        "{{CONFIG_DRIFT_SUMMARY}}": config_drift_summary,
        "{{TOTAL_RUNS_SUMMARY}}": total_runs_summary,
        "{{PER_HOST_SUMMARY}}": "\n".join(per_host_blocks).strip(),
        "{{MILESTONE_BREAKDOWN}}": "\n".join(milestone_lines),
        "{{ATTRIBUTION_TABLE}}": "\n".join(attr_lines),
        "{{GROUP_BREAKDOWN}}": group_table,
        "{{UTTERANCE_BREAKDOWN}}": utterance_table,
        "{{EDGE_AND_CHECKLIST_BREAKDOWN}}": "\n".join(edge_lines),
        "{{FAILURES_TABLE}}": failures_table,
        "{{NOTES_SECTION}}": "\n".join(notes_parts),
    }
    rendered = template
    for token, value in replacements.items():
        rendered = rendered.replace(token, value)
    return rendered


def simctl(*args: str, timeout: int = 60, check: bool = True) -> str:
    res = subprocess.run(["xcrun", "simctl", *args], text=True, capture_output=True, timeout=timeout)
    if check and res.returncode != 0:
        raise RuntimeError(f"simctl {' '.join(args)} failed ({res.returncode}): {res.stderr.strip()} {res.stdout.strip()}")
    return res.stdout


def lookup_simulator_info(udid: str) -> dict[str, str]:
    raw = json.loads(simctl("list", "devices", "-j", timeout=30))
    devices = raw.get("devices", {})
    for runtime_id, items in devices.items():
        if not isinstance(items, list):
            continue
        for item in items:
            if isinstance(item, dict) and str(item.get("udid", "")).upper() == udid.upper():
                os_label = runtime_id.rsplit(".", 1)[-1].replace("-", " ")
                return {
                    "udid": str(item["udid"]),
                    "name": str(item.get("name") or "Simulator"),
                    "state": str(item.get("state") or "Unknown"),
                    "os_version": os_label,
                    "device_type": str(item.get("deviceTypeIdentifier") or ""),
                }
    raise ValueError(f"UDID {udid!r} is not a known iOS Simulator device; refusing to touch non-simulator devices")


def simulator_device_model(sim_info: dict[str, str]) -> str:
    device_type = str(sim_info.get("device_type") or "").strip()
    if device_type:
        return device_type.rsplit(".", 1)[-1].replace("-", " ")
    return str(sim_info.get("name") or "iPhone Simulator")


def resolve_simulator_spec(device_type: str | None = None, runtime: str | None = None) -> tuple[str, str]:
    if device_type is None:
        dev_list = json.loads(simctl("list", "-j", "devicetypes")).get("devicetypes", [])
        iphones = [d["identifier"] for d in dev_list if "iPhone" in d.get("name", "") and d.get("identifier")]
        if not iphones:
            raise RuntimeError("no iPhone simulator device type available")
        preferred = [d for d in iphones if "iPhone-18-Pro" in d or "iPhone-17" in d]
        device_type = preferred[0] if preferred else iphones[-1]
    if runtime is None:
        rt_list = json.loads(simctl("list", "-j", "runtimes")).get("runtimes", [])
        ios_runtimes = [
            r for r in rt_list
            if r.get("isAvailable") and str(r.get("identifier", "")).startswith("com.apple.CoreSimulator.SimRuntime.iOS-")
        ]
        if not ios_runtimes:
            raise RuntimeError("no available iOS simulator runtime found")
        ios_runtimes.sort(key=lambda r: tuple(int(p) for p in re.findall(r"\d+", str(r.get("version", ""))) or [0]))
        runtime = ios_runtimes[-1]["identifier"]
    return device_type, runtime


@contextmanager
def simulator_context(udid: str | None, device_type: str | None, runtime: str | None):
    if udid is not None:
        info = lookup_simulator_info(udid)
        if info["state"] != "Booted":
            simctl("boot", info["udid"], timeout=120)
            simctl("bootstatus", info["udid"], "-b", timeout=180)
        yield info
        return

    resolved_type, resolved_runtime = resolve_simulator_spec(device_type, runtime)
    name = f"Poki-Voice-Compare-{os.getpid()}-{int(time.time())}"
    created = simctl("create", name, resolved_type, resolved_runtime, timeout=60).strip()
    if not created:
        raise RuntimeError("simctl create returned empty UDID")
    OWNED_SIMULATORS.add(created)
    try:
        simctl("boot", created, timeout=120)
        simctl("bootstatus", created, "-b", timeout=180)
        yield lookup_simulator_info(created)
    finally:
        OWNED_SIMULATORS.discard(created)
        simctl("shutdown", created, check=False, timeout=30)
        simctl("delete", created, check=False, timeout=60)


def read_app_metadata(app_path: Path) -> dict[str, str]:
    info_plist = app_path / "Info.plist"
    if not info_plist.is_file():
        raise FileNotFoundError(f"missing Info.plist in {app_path}")
    info = plistlib.loads(info_plist.read_bytes())
    return {
        "bundle_id": str(info["CFBundleIdentifier"]),
        "xcode_build": str(info.get("DTXcodeBuild") or "unknown"),
        "sdk_build": str(info.get("DTSDKBuild") or "unknown"),
        "app_version": str(info.get("CFBundleShortVersionString") or "unknown"),
    }


def _locale_args(locale: str) -> list[str]:
    if locale.startswith("zh"):
        return ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
    return ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]


def _read_log_text(log_path: Path) -> str:
    if not log_path.exists():
        return ""
    return log_path.read_text(encoding="utf-8", errors="replace")


def _host_load_1m() -> float | None:
    try:
        return round(os.getloadavg()[0], 2)
    except OSError:
        return None


def _find_bridge_turn_report(path: Path | None, lines_before: int, utterance_index: int) -> dict[str, Any] | None:
    if not path or not path.exists():
        return None
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    for raw_line in lines[lines_before:]:
        if not raw_line.strip():
            continue
        try:
            parsed_line = json.loads(raw_line)
        except json.JSONDecodeError:
            continue
        if int(parsed_line.get("n", -1)) == utterance_index:
            return parsed_line
    return None


def run_simulator_trial(
    *,
    sim_info: dict[str, str],
    target: BuildTarget,
    changed_variable: str,
    entry_mode: str,
    round_num: int,
    order_index: int,
    sample: dict[str, Any],
    timeout_s: float,
    out_dir: Path,
    bridge_url: str | None = None,
    bridge_report_jsonl: Path | None = None,
) -> dict[str, Any]:
    app_meta = read_app_metadata(target.app_path)
    bid = app_meta["bundle_id"]
    udid = sim_info["udid"]
    run_id = f"r{round_num:02d}_{order_index:03d}_{target.side}_{sample['id']}"
    run_dir = out_dir / "runs" / run_id
    run_dir.mkdir(parents=True, exist_ok=True)

    simctl("terminate", udid, bid, check=False, timeout=20)
    simctl("install", udid, str(target.app_path), timeout=90)
    data_dir = Path(simctl("get_app_container", udid, bid, "data", timeout=20).strip())
    poki_log = data_dir / "Library/Caches/poki-log.txt"
    if poki_log.exists():
        poki_log.unlink()

    bridge_lines_before = 0
    if bridge_report_jsonl and bridge_report_jsonl.exists():
        bridge_lines_before = len(bridge_report_jsonl.read_text(encoding="utf-8", errors="replace").splitlines())

    launch_args = ["launch", "--terminate-running-process", udid, bid, *_locale_args(sample.get("locale", "en"))]
    if entry_mode == "rehearsal":
        variant = sample.get("rehearsal_variant") or "1"
        launch_args.extend(["-pokiTalk", "talk", "-pokiTalkRehearsal", str(variant)])
    elif entry_mode == "bridge_replay":
        if not bridge_url:
            raise ValueError("--bridge-url is required for --entry-mode bridge_replay")
        n = int(sample["utterance_index"])
        link = f"poki://voice?bridge={quote(bridge_url, safe='')}&test={n}-{n}&muted=1"
        launch_args.extend(["-pokiVoiceLink", link])
    else:
        raise ValueError(f"unsupported entry_mode {entry_mode!r}")

    env_meta = {
        "surface": "ios_simulator",
        "device_model": simulator_device_model(sim_info),
        "os_version": sim_info["os_version"],
        "xcode_build": app_meta["xcode_build"],
        "sdk_build": app_meta["sdk_build"],
        "cpu_count": os.cpu_count(),
        "load_avg_1m": _host_load_1m(),
    }

    t_start = time.monotonic()
    timed_out = False
    bridge_turn_report: dict[str, Any] | None = None
    log_slice = ""

    try:
        simctl(*launch_args, timeout=30)
        deadline = t_start + timeout_s
        while time.monotonic() < deadline:
            log_slice = _read_log_text(poki_log)
            if entry_mode == "rehearsal":
                variant = str(sample.get("rehearsal_variant") or "1")
                if variant == "lost":
                    if "[voice] connection lost:" in log_slice:
                        time.sleep(1.2)
                        log_slice = _read_log_text(poki_log)
                        break
                else:
                    has_turn = "[voice] turn: end of speech to spoken result" in log_slice
                    has_stop = "reply playback stopped (model event)" in log_slice
                    if has_turn and has_stop:
                        time.sleep(1.2)
                        log_slice = _read_log_text(poki_log)
                        break
            else:
                bridge_turn_report = _find_bridge_turn_report(
                    bridge_report_jsonl, bridge_lines_before, int(sample["utterance_index"])
                )
                if bridge_turn_report is not None or "[voice] test run finished" in log_slice:
                    time.sleep(1.2)
                    log_slice = _read_log_text(poki_log)
                    if bridge_turn_report is None:
                        bridge_turn_report = _find_bridge_turn_report(
                            bridge_report_jsonl, bridge_lines_before, int(sample["utterance_index"])
                        )
                    break
            time.sleep(0.25)
        else:
            timed_out = True
            log_slice = _read_log_text(poki_log)
    finally:
        simctl("terminate", udid, bid, check=False, timeout=20)

    wall_ms = int(round((time.monotonic() - t_start) * 1000))
    (run_dir / "poki-log-slice.txt").write_text(log_slice, encoding="utf-8")
    parsed = parse_poki_log(log_slice, entry_mode=entry_mode, sample=sample, timed_out=timed_out)

    if entry_mode == "bridge_replay" and bridge_turn_report is not None:
        return record_from_bridge_report(
            bridge_turn_report,
            side=target.side,
            build_label=target.label,
            commit_sha=target.commit,
            changed_variable=changed_variable,
            round_num=round_num,
            order_index=order_index,
            sample=sample,
            environment=env_meta,
            config_fingerprint=parsed["config_fingerprint"],
            log_parsed=parsed,
            wall_ms=wall_ms,
        )

    return {
        "schema": SCHEMA_VERSION,
        "run_id": run_id,
        "round": round_num,
        "order_index": order_index,
        "side": target.side,
        "build_label": target.label,
        "commit_sha": target.commit,
        "changed_variable": changed_variable,
        "entry_mode": entry_mode,
        "sample_id": sample["id"],
        "utterance_index": sample["utterance_index"],
        "voice_host": parsed["voice_host"],
        "action_host": parsed["action_host"],
        "entry_route": parsed["entry_route"],
        "observation_source": parsed["observation_source"],
        "group": sample["group"],
        "utterance_class": sample["utterance_class"],
        "checklist_category": sample["checklist_category"],
        "edge_flags": list(sample.get("edge_flags") or []),
        "locale": sample.get("locale", "en"),
        "environment": env_meta,
        "config_fingerprint": parsed["config_fingerprint"],
        "status": parsed["status"],
        "timeout": parsed["timeout"],
        "error": parsed["error"],
        "target_confirmed": parsed["target_confirmed"],
        "verified_success": parsed["verified_success"],
        "premature_truncation": parsed["premature_truncation"],
        "duplicate_inputs": parsed["duplicate_inputs"],
        "false_completion_announced": parsed["false_completion_announced"],
        "model_roundtrips": parsed["model_roundtrips"],
        "tool_calls": parsed["tool_calls"],
        "milestones_ms": parsed["milestones_ms"],
        "derived_ms": {
            "action_to_confirmed_ms": parsed["derived_ms"]["action_to_confirmed_ms"],
            "wall_ms": wall_ms,
        },
        "host_ms": parsed["host_ms"],
        "timing_source": parsed["timing_source"],
        "notes": "",
    }


def load_measurements_jsonl(paths: list[Path]) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    for path in paths:
        for line_no, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
            stripped = raw.strip()
            if not stripped:
                continue
            try:
                records.append(json.loads(stripped))
            except json.JSONDecodeError as exc:
                raise ValueError(f"{path}:{line_no}: invalid JSON: {exc}") from exc
    return records


def _parse_iso_timestamp(raw: Any) -> float | None:
    if not isinstance(raw, str) or not raw.strip():
        return None
    text = raw.strip()
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    try:
        return datetime.fromisoformat(text).timestamp()
    except ValueError:
        return None


def cmd_validate(args: argparse.Namespace) -> int:
    manifest = load_samples_manifest(args.samples)
    errors = validate_samples_manifest(manifest)
    if errors:
        for err in errors:
            print(f"INVALID: {err}", file=sys.stderr)
        return 1
    print(f"OK: {len(manifest['samples'])} samples validated ({args.samples})")
    return 0


def select_samples(
    manifest: dict[str, Any],
    *,
    entry_mode: str,
    sample_ids: str | None = None,
    voice_host: str | None = None,
) -> list[dict[str, Any]]:
    all_samples = manifest["samples"]
    if sample_ids:
        wanted = [s.strip() for s in sample_ids.split(",") if s.strip()]
        by_id = {s["id"]: s for s in all_samples}
        missing = [w for w in wanted if w not in by_id]
        if missing:
            raise ValueError(f"unknown sample IDs: {', '.join(missing)}")
        selected = [by_id[w] for w in wanted]
        incompatible = [s["id"] for s in selected if entry_mode not in (s.get("entry_modes") or [])]
        if incompatible:
            raise ValueError(
                f"sample IDs incompatible with entry_mode={entry_mode!r}: {', '.join(incompatible)}"
            )
    else:
        selected = [s for s in all_samples if entry_mode in (s.get("entry_modes") or [])]
    if voice_host:
        selected = [s for s in selected if s.get("voice_host") == voice_host]
    if not selected:
        raise ValueError(f"no samples selected for entry_mode={entry_mode!r} voice_host={voice_host!r}")
    return selected


def cmd_run(args: argparse.Namespace) -> int:
    baseline = parse_target_spec(args.baseline, "baseline")
    candidate = parse_target_spec(args.candidate, "candidate")
    manifest = load_samples_manifest(args.samples)
    errors = validate_samples_manifest(manifest)
    if errors:
        raise ValueError("sample manifest invalid: " + "; ".join(errors))

    selected = select_samples(
        manifest,
        entry_mode=args.entry_mode,
        sample_ids=args.sample_ids,
        voice_host=args.voice_host,
    )

    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    jsonl_path = out_dir / "measurements.jsonl"
    if jsonl_path.exists():
        jsonl_path.unlink()

    schedule = build_alternating_schedule(selected, args.rounds)
    targets = {"baseline": baseline, "candidate": candidate}
    records: list[dict[str, Any]] = []

    with simulator_context(args.udid, args.device_type, args.runtime) as sim_info:
        for round_num, order_index, side, sample in schedule:
            record = run_simulator_trial(
                sim_info=sim_info,
                target=targets[side],
                changed_variable=args.changed_variable,
                entry_mode=args.entry_mode,
                round_num=round_num,
                order_index=order_index,
                sample=sample,
                timeout_s=args.timeout,
                out_dir=out_dir,
                bridge_url=args.bridge_url,
                bridge_report_jsonl=args.bridge_report_jsonl,
            )
            records.append(record)
            with jsonl_path.open("a", encoding="utf-8") as fh:
                fh.write(json.dumps(record, ensure_ascii=False) + "\n")
            sp = record["milestones_ms"].get("spoken_ms")
            tc = record["milestones_ms"].get("target_confirmed_ms")
            print(
                f"[r{round_num:02d} #{order_index:02d}] {side:9s} {sample['id']:30s} "
                f"status={record['status']:7s} confirmed={str(record['target_confirmed']).lower():5s} "
                f"target_ms={tc if tc is not None else 'n/a'} spoken_ms={sp if sp is not None else 'n/a'} "
                f"wall_ms={record['derived_ms'].get('wall_ms')} {record['error']}".rstrip(),
                flush=True,
            )

    allow_diff = {k.strip() for k in (args.allow_config_diff or "").split(",") if k.strip()}
    evaluation = evaluate_comparison(
        records,
        primary_metric=args.primary_metric,
        min_rounds=args.min_rounds,
        allow_config_diff=allow_diff,
    )
    report_md = render_report(
        records,
        evaluation,
        template_path=args.template,
        limiter_note=args.limiter or "",
    )
    (out_dir / "report.md").write_text(report_md, encoding="utf-8")
    (out_dir / "summary.json").write_text(dumps_json(evaluation) + "\n", encoding="utf-8")
    print(f"\nVerdict: {evaluation['overall_verdict']} ({evaluation['overall_detail']})", flush=True)
    for reason in evaluation["overall_reasons"]:
        print(f"  - {reason}", flush=True)
    print(f"Report written to {out_dir / 'report.md'}", flush=True)
    if args.exit_on_not_faster and evaluation["overall_verdict"] != "speedup":
        return 1
    return 0


def cmd_report(args: argparse.Namespace) -> int:
    records = load_measurements_jsonl([Path(p) for p in args.input])
    allow_diff = {k.strip() for k in (args.allow_config_diff or "").split(",") if k.strip()}
    evaluation = evaluate_comparison(
        records,
        primary_metric=args.primary_metric,
        min_rounds=args.min_rounds,
        allow_config_diff=allow_diff,
    )
    report_md = render_report(
        records,
        evaluation,
        template_path=args.template,
        limiter_note=args.limiter or "",
        replay_note=args.replay_note or "",
    )
    if args.out:
        out_path = Path(args.out)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(report_md, encoding="utf-8")
    else:
        print(report_md)
    if args.json_out:
        json_path = Path(args.json_out)
        json_path.parent.mkdir(parents=True, exist_ok=True)
        json_path.write_text(dumps_json(evaluation) + "\n", encoding="utf-8")
    if args.exit_on_not_faster and evaluation["overall_verdict"] != "speedup":
        return 1
    return 0


def _fallback_sample_for_index(idx: int) -> dict[str, Any]:
    return {
        "id": f"utterance-{idx:02d}",
        "utterance_index": idx,
        "voice_host": "voice_bridge",
        "expected_action_host": "phone_local",
        "group": "warm_session",
        "utterance_class": "short_command",
        "checklist_category": "core_speed",
        "edge_flags": [],
        "locale": "en",
    }


def cmd_ingest_bridge(args: argparse.Namespace) -> int:
    manifest = load_samples_manifest(args.samples)
    by_index = {int(s["utterance_index"]): s for s in manifest["samples"]}
    base_raw = load_measurements_jsonl([Path(args.baseline_jsonl)])
    cand_raw = load_measurements_jsonl([Path(args.candidate_jsonl)])

    tagged: list[tuple[str, int, dict[str, Any]]] = [
        ("baseline", i, row) for i, row in enumerate(base_raw)
    ] + [
        ("candidate", i, row) for i, row in enumerate(cand_raw)
    ]

    all_have_at = bool(tagged) and all(_parse_iso_timestamp(row.get("at")) is not None for _, _, row in tagged)
    records: list[dict[str, Any]] = []

    if all_have_at:
        ordered = sorted(
            tagged,
            key=lambda item: (_parse_iso_timestamp(item[2].get("at")) or 0.0, 0 if item[0] == "baseline" else 1, item[1]),
        )
        round_counter: dict[tuple[str, int], int] = {}
        for order_index, (side, _, row) in enumerate(ordered):
            idx = int(row.get("n", 0))
            sample = by_index.get(idx, _fallback_sample_for_index(idx))
            round_counter[(side, idx)] = round_counter.get((side, idx), 0) + 1
            records.append(
                record_from_bridge_report(
                    row,
                    side=side,
                    build_label=args.baseline_label if side == "baseline" else args.candidate_label,
                    commit_sha=args.baseline_commit if side == "baseline" else args.candidate_commit,
                    changed_variable=args.changed_variable,
                    round_num=round_counter[(side, idx)],
                    order_index=order_index,
                    sample=sample,
                )
            )
    elif args.interleaved:
        def bucket_by_index(rows: list[dict[str, Any]]) -> dict[int, list[dict[str, Any]]]:
            grouped: dict[int, list[dict[str, Any]]] = {}
            for row in rows:
                grouped.setdefault(int(row.get("n", 0)), []).append(row)
            return grouped

        b_grouped = bucket_by_index(base_raw)
        c_grouped = bucket_by_index(cand_raw)
        all_indices = sorted(set(b_grouped) | set(c_grouped))
        order_index = 0
        max_rounds = max(
            max((len(v) for v in b_grouped.values()), default=0),
            max((len(v) for v in c_grouped.values()), default=0),
        )
        for rnd in range(1, max_rounds + 1):
            sides = ("baseline", "candidate") if rnd % 2 == 1 else ("candidate", "baseline")
            for idx in all_indices:
                sample = by_index.get(idx, _fallback_sample_for_index(idx))
                for side in sides:
                    source_list = b_grouped.get(idx, []) if side == "baseline" else c_grouped.get(idx, [])
                    if rnd - 1 >= len(source_list):
                        continue
                    records.append(
                        record_from_bridge_report(
                            source_list[rnd - 1],
                            side=side,
                            build_label=args.baseline_label if side == "baseline" else args.candidate_label,
                            commit_sha=args.baseline_commit if side == "baseline" else args.candidate_commit,
                            changed_variable=args.changed_variable,
                            round_num=rnd,
                            order_index=order_index,
                            sample=sample,
                        )
                    )
                    order_index += 1
    else:
        round_counter = {}
        for order_index, (side, _, row) in enumerate(tagged):
            idx = int(row.get("n", 0))
            sample = by_index.get(idx, _fallback_sample_for_index(idx))
            round_counter[(side, idx)] = round_counter.get((side, idx), 0) + 1
            records.append(
                record_from_bridge_report(
                    row,
                    side=side,
                    build_label=args.baseline_label if side == "baseline" else args.candidate_label,
                    commit_sha=args.baseline_commit if side == "baseline" else args.candidate_commit,
                    changed_variable=args.changed_variable,
                    round_num=round_counter[(side, idx)],
                    order_index=order_index,
                    sample=sample,
                )
            )

    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    jsonl_path = out_dir / "measurements.jsonl"
    jsonl_path.write_text(
        "\n".join(json.dumps(r, ensure_ascii=False) for r in records) + ("\n" if records else ""),
        encoding="utf-8",
    )
    allow_diff = {k.strip() for k in (args.allow_config_diff or "").split(",") if k.strip()}
    evaluation = evaluate_comparison(
        records,
        primary_metric=args.primary_metric,
        min_rounds=args.min_rounds,
        allow_config_diff=allow_diff,
    )
    report_md = render_report(
        records,
        evaluation,
        template_path=args.template,
        limiter_note=args.limiter or "",
    )
    (out_dir / "report.md").write_text(report_md, encoding="utf-8")
    (out_dir / "summary.json").write_text(dumps_json(evaluation) + "\n", encoding="utf-8")
    if args.exit_on_not_faster and evaluation["overall_verdict"] != "speedup":
        return 1
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Alternating voice speed and correctness comparison harness for Poki."
    )
    sub = parser.add_subparsers(dest="command", required=True)

    p_val = sub.add_parser("validate", help="Validate a voice comparison sample manifest.")
    p_val.add_argument("--samples", type=Path, default=DEFAULT_SAMPLES_PATH)
    p_val.set_defaults(func=cmd_validate)

    p_run = sub.add_parser("run", help="Run alternating baseline vs candidate trials on an iOS Simulator.")
    p_run.add_argument("--baseline", required=True, help="label=commit=/path/to/Poki.app")
    p_run.add_argument("--candidate", required=True, help="label=commit=/path/to/Poki.app")
    p_run.add_argument("--changed-variable", required=True, help="Single variable changed between baseline and candidate")
    p_run.add_argument("--samples", type=Path, default=DEFAULT_SAMPLES_PATH)
    p_run.add_argument("--sample-ids", default=None, help="Optional comma-separated sample IDs")
    p_run.add_argument("--voice-host", choices=VOICE_HOSTS, default=None, help="Optional voice host filter")
    p_run.add_argument("--entry-mode", choices=("rehearsal", "bridge_replay"), default="rehearsal")
    p_run.add_argument("--rounds", type=int, default=5)
    p_run.add_argument("--min-rounds", type=int, default=5)
    p_run.add_argument("--primary-metric", choices=PRIMARY_METRICS, default="target_confirmed_ms")
    p_run.add_argument("--timeout", type=float, default=35.0)
    p_run.add_argument("--udid", default=None, help="Optional existing iOS Simulator UDID (never deleted)")
    p_run.add_argument("--device-type", default=None)
    p_run.add_argument("--runtime", default=None)
    p_run.add_argument("--bridge-url", default=None, help="Bridge URL for --entry-mode bridge_replay")
    p_run.add_argument("--bridge-report-jsonl", type=Path, default=None)
    p_run.add_argument("--allow-config-diff", default="")
    p_run.add_argument("--limiter", default="")
    p_run.add_argument("--template", type=Path, default=DEFAULT_TEMPLATE_PATH)
    p_run.add_argument("--out", required=True)
    p_run.add_argument("--exit-on-not-faster", action="store_true")
    p_run.set_defaults(func=cmd_run)

    p_rep = sub.add_parser("report", help="Evaluate raw measurements.jsonl and render a Markdown report.")
    p_rep.add_argument("--input", action="append", required=True, help="Path to measurements.jsonl (repeatable)")
    p_rep.add_argument("--primary-metric", choices=PRIMARY_METRICS, default="target_confirmed_ms")
    p_rep.add_argument("--min-rounds", type=int, default=5)
    p_rep.add_argument("--allow-config-diff", default="")
    p_rep.add_argument("--limiter", default="")
    p_rep.add_argument("--replay-note", default="")
    p_rep.add_argument("--template", type=Path, default=DEFAULT_TEMPLATE_PATH)
    p_rep.add_argument("--out", default=None)
    p_rep.add_argument("--json-out", default=None)
    p_rep.add_argument("--exit-on-not-faster", action="store_true")
    p_rep.set_defaults(func=cmd_report)

    p_ing = sub.add_parser("ingest-bridge", help="Import baseline/candidate voice-test-report.jsonl and render a report.")
    p_ing.add_argument("--baseline-jsonl", required=True)
    p_ing.add_argument("--candidate-jsonl", required=True)
    p_ing.add_argument("--baseline-label", default="baseline")
    p_ing.add_argument("--candidate-label", default="candidate")
    p_ing.add_argument("--baseline-commit", required=True)
    p_ing.add_argument("--candidate-commit", required=True)
    p_ing.add_argument("--changed-variable", required=True)
    p_ing.add_argument("--samples", type=Path, default=DEFAULT_SAMPLES_PATH)
    p_ing.add_argument("--primary-metric", choices=PRIMARY_METRICS, default="target_confirmed_ms")
    p_ing.add_argument("--min-rounds", type=int, default=5)
    p_ing.add_argument("--allow-config-diff", default="")
    p_ing.add_argument("--limiter", default="")
    p_ing.add_argument("--template", type=Path, default=DEFAULT_TEMPLATE_PATH)
    p_ing.add_argument("--out", required=True)
    p_ing.add_argument("--interleaved", action="store_true", help="Assert timestamp-less inputs were run interleaved")
    p_ing.add_argument("--exit-on-not-faster", action="store_true")
    p_ing.set_defaults(func=cmd_ingest_bridge)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return int(args.func(args))


if __name__ == "__main__":
    sys.exit(main())
