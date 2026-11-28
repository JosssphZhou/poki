#!/usr/bin/env python3
import importlib.util
import json
import plistlib
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

SCRIPT_PATH = Path(__file__).with_name("compare-voice-speed.py")
SAMPLES_PATH = Path(__file__).with_name("voice-compare") / "samples.json"
SPEC = importlib.util.spec_from_file_location("compare_voice_speed", SCRIPT_PATH)
MOD = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MOD
SPEC.loader.exec_module(MOD)


def make_record(
    *,
    side: str,
    round_num: int,
    order_index: int,
    sample_id: str = "pd-warm-short-calc7-zh",
    voice_host: str = "phone_direct",
    action_host: str = "phone_local",
    entry_route: str = "direct_ephemeral_credential",
    observation_source: str = "phone_tree_and_screenshot",
    group: str = "warm_session",
    utterance_class: str = "short_command",
    checklist_category: str = "core_speed",
    edge_flags: list[str] | None = None,
    status: str = "ok",
    timeout: bool = False,
    error: str = "",
    target_confirmed: bool = True,
    target_confirmed_ms: int | None = 1000,
    first_effective_action_ms: int | None = 400,
    spoken_ms: int | None = 1300,
    delivered_ms: int | None = 1020,
    premature_truncation: bool = False,
    duplicate_inputs: int = 0,
    false_completion_announced: bool = False,
    model_roundtrips: int = 2,
    changed_variable: str = "post-action-fresh-frame",
    config_fingerprint: dict | None = None,
    mac_tools_ms: int | None = None,
) -> dict:
    a2c = (
        max(0, target_confirmed_ms - first_effective_action_ms)
        if target_confirmed_ms is not None and first_effective_action_ms is not None
        else None
    )
    verified = status == "ok" and not timeout and target_confirmed and not false_completion_announced
    return {
        "schema": MOD.SCHEMA_VERSION,
        "run_id": f"r{round_num:02d}_{order_index:03d}_{side}_{sample_id}",
        "round": round_num,
        "order_index": order_index,
        "side": side,
        "build_label": side,
        "commit_sha": "base111" if side == "baseline" else "cand222",
        "changed_variable": changed_variable,
        "entry_mode": "bridge_replay",
        "sample_id": sample_id,
        "utterance_index": 5,
        "voice_host": voice_host,
        "action_host": action_host,
        "entry_route": entry_route,
        "observation_source": observation_source,
        "group": group,
        "utterance_class": utterance_class,
        "checklist_category": checklist_category,
        "edge_flags": edge_flags if edge_flags is not None else ["animation_enabled"],
        "locale": "zh-Hans",
        "environment": {
            "surface": "ios_simulator",
            "device_model": "iPhone 18 Pro",
            "os_version": "iOS 27.2",
            "xcode_build": "27C5020n",
            "cpu_count": 30,
            "load_avg_1m": 12.5,
        },
        "config_fingerprint": config_fingerprint or {"model": "gpt-live-1.1", "vad": "server_vad", "locale": "zh-Hans"},
        "status": status,
        "timeout": timeout,
        "error": error,
        "target_confirmed": target_confirmed,
        "verified_success": verified,
        "premature_truncation": premature_truncation,
        "duplicate_inputs": duplicate_inputs,
        "false_completion_announced": false_completion_announced,
        "model_roundtrips": model_roundtrips,
        "tool_calls": ["do"],
        "milestones_ms": {
            "said_ms": 0,
            "heard_ms": 90,
            "call_ms": 220,
            "first_effective_action_ms": first_effective_action_ms,
            "tool_done_ms": target_confirmed_ms,
            "target_confirmed_ms": target_confirmed_ms if target_confirmed else None,
            "delivered_ms": delivered_ms,
            "spoken_ms": spoken_ms,
        },
        "derived_ms": {"action_to_confirmed_ms": a2c, "wall_ms": (spoken_ms or 1500) + 500},
        "host_ms": {
            "phone_local_ms": 420 if action_host == "phone_local" else None,
            "mac_tools_ms": mac_tools_ms,
            "mac_tools_roundtrip_ms": mac_tools_ms,
        },
        "timing_source": "voice-timing",
        "notes": "",
    }


def make_paired_rounds(baseline_specs: list[dict], candidate_specs: list[dict]) -> list[dict]:
    records = []
    order = 0
    for idx, (b_kw, c_kw) in enumerate(zip(baseline_specs, candidate_specs), start=1):
        pair = (("baseline", b_kw), ("candidate", c_kw)) if idx % 2 == 1 else (("candidate", c_kw), ("baseline", b_kw))
        for side, kw in pair:
            records.append(make_record(side=side, round_num=idx, order_index=order, **kw))
            order += 1
    return records


class VoiceSpeedCompareTests(unittest.TestCase):
    def test_sample_manifest_validates_all_required_dimensions_via_cli(self):
        proc = subprocess.run(
            [sys.executable, str(SCRIPT_PATH), "validate", "--samples", str(SAMPLES_PATH)],
            text=True,
            capture_output=True,
            timeout=15,
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("OK:", proc.stdout)

        manifest = MOD.load_samples_manifest(SAMPLES_PATH)
        self.assertEqual(MOD.validate_samples_manifest(manifest), [])

        missing_host = json.loads(json.dumps(manifest))
        missing_host["samples"] = [s for s in missing_host["samples"] if s["voice_host"] != "voice_bridge"]
        self.assertTrue(any("voice_bridge" in e for e in MOD.validate_samples_manifest(missing_host)))

        bad_action_host = json.loads(json.dumps(manifest))
        bad_action_host["samples"][0]["expected_action_host"] = "mac_tools"
        self.assertTrue(any("mac_tools" in e for e in MOD.validate_samples_manifest(bad_action_host)))

    def test_faster_candidate_with_lower_success_rate_is_judged_not_faster_via_cli(self):
        baseline_specs = [
            {"target_confirmed_ms": 1200 + i * 10, "spoken_ms": 1500 + i * 10}
            for i in range(5)
        ]
        candidate_specs = [
            {"target_confirmed_ms": 780 + i * 10, "spoken_ms": 1020 + i * 10}
            for i in range(4)
        ] + [
            {
                "status": "failed",
                "target_confirmed": False,
                "target_confirmed_ms": None,
                "spoken_ms": 950,
                "error": "target text 7 never appeared after tap",
            }
        ]
        records = make_paired_rounds(baseline_specs, candidate_specs)

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            in_jsonl = root / "measurements.jsonl"
            out_md = root / "report.md"
            out_json = root / "summary.json"
            in_jsonl.write_text("\n".join(json.dumps(r) for r in records) + "\n", encoding="utf-8")

            proc = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT_PATH),
                    "report",
                    "--input", str(in_jsonl),
                    "--out", str(out_md),
                    "--json-out", str(out_json),
                    "--exit-on-not-faster",
                ],
                text=True,
                capture_output=True,
                timeout=15,
            )
            self.assertEqual(proc.stderr, "", f"CLI crashed instead of exiting via verdict gate:\n{proc.stderr}")
            self.assertEqual(proc.returncode, 1)
            self.assertTrue(out_json.is_file())
            self.assertTrue(out_md.is_file())
            summary = json.loads(out_json.read_text(encoding="utf-8"))
            report = out_md.read_text(encoding="utf-8")

        self.assertEqual(summary["overall_verdict"], "not_faster")
        self.assertEqual(summary["overall_detail"], "regressed")
        self.assertAlmostEqual(summary["hosts"]["phone_direct"]["baseline"]["primary_verified"]["p50"], 1220.0)
        self.assertTrue(any("success_rate_regressed" in r for r in summary["overall_reasons"]), summary["overall_reasons"])
        self.assertIn("**NOT FASTER (regressed)**", report)
        self.assertIn("target text 7 never appeared after tap", report)
        self.assertIn("80.0% (4/5)", report)
        self.assertIn("100.0% (5/5)", report)
        self.assertIsNone(re.search(r"\b\d+(?:\.\d+)?x\s+faster\b", report, re.I))

    def test_report_counts_only_independent_paired_observations_via_cli(self):
        records = make_paired_rounds(
            [{"target_confirmed_ms": 1200}] * 5,
            [{"target_confirmed_ms": 800}] * 5,
        )
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            datasets = {
                "one-pair": records[:2],
                "first-three": records[:6],
                "third-and-fourth": records[4:8],
                "last-three": records[4:],
                "unique": records,
                "same-round": [dict(r, round=1) for r in records],
                "unpaired": [
                    dict(r, round=r["round"] + 5)
                    if r["side"] == "candidate" and r["round"] > 1 else r
                    for r in records
                ],
            }
            for name, rows in datasets.items():
                (root / f"{name}.jsonl").write_text(
                    "\n".join(json.dumps(r, sort_keys=(name == "last-three")) for r in rows) + "\n",
                    encoding="utf-8",
                )

            cases = (
                ("repeated-file", ["one-pair"] * 5, 2, "insufficient_rounds"),
                ("overlap-below-minimum", ["first-three", "third-and-fourth"], 8, "insufficient_rounds"),
                ("unique-pairs", ["unique"], 10, None),
                ("overlap-with-five-pairs", ["first-three", "last-three"], 10, None),
                ("distinct-records-one-round", ["same-round"], 10, "insufficient_rounds"),
                ("equal-counts-unpaired-rounds", ["unpaired"], 10, "unmatched_sample_set"),
            )
            for name, inputs, total, reason in cases:
                with self.subTest(case=name):
                    summary_path = root / f"{name}-summary.json"
                    proc = subprocess.run(
                        [
                            sys.executable, str(SCRIPT_PATH), "report",
                            *[arg for source in inputs for arg in ("--input", str(root / f"{source}.jsonl"))],
                            "--json-out", str(summary_path), "--exit-on-not-faster",
                        ],
                        text=True,
                        capture_output=True,
                        timeout=15,
                    )
                    summary = json.loads(summary_path.read_text(encoding="utf-8"))
                    self.assertEqual(proc.stderr, "")
                    self.assertEqual(proc.returncode, 1 if reason else 0, summary["overall_reasons"])
                    self.assertEqual(summary["total_records"], total)
                    self.assertEqual(summary["hosts"]["phone_direct"]["baseline"]["total"], total // 2)
                    self.assertEqual(summary["hosts"]["phone_direct"]["candidate"]["total"], total // 2)
                    if reason:
                        self.assertEqual(summary["overall_verdict"], "not_faster")
                        self.assertEqual(summary["overall_detail"], "inconclusive")
                        self.assertTrue(any(reason in r for r in summary["overall_reasons"]))
                        self.assertIn("**NOT FASTER (inconclusive)**", proc.stdout)
                    else:
                        self.assertEqual(summary["overall_verdict"], "speedup")
                        self.assertIn("**SPEEDUP**", proc.stdout)

    def test_speedup_verdict_gates_confirmation_variation_tail_and_safety_counters(self):
        good_records = make_paired_rounds(
            [{"target_confirmed_ms": 1200 + i * 5} for i in range(5)],
            [{"target_confirmed_ms": 920 + i * 5} for i in range(5)],
        )
        good_eval = MOD.evaluate_comparison(good_records)
        self.assertEqual(good_eval["overall_verdict"], "speedup", good_eval["overall_reasons"])

        multi_sample_records: list[dict] = []
        order = 0
        for rnd in range(1, 6):
            sides = ("baseline", "candidate") if rnd % 2 == 1 else ("candidate", "baseline")
            for sid, base_ms, cand_ms in (("s-fast", 600, 420), ("s-slow", 2600, 1900)):
                for side in sides:
                    ms = (base_ms if side == "baseline" else cand_ms) + rnd * 5
                    multi_sample_records.append(
                        make_record(side=side, round_num=rnd, order_index=order, sample_id=sid, target_confirmed_ms=ms)
                    )
                    order += 1
        multi_eval = MOD.evaluate_comparison(multi_sample_records)
        self.assertEqual(multi_eval["overall_verdict"], "speedup", multi_eval["overall_reasons"])
        self.assertLess(multi_eval["hosts"]["phone_direct"]["noise_floor_ms"], 50.0)

        unconfirmed_records = make_paired_rounds(
            [{"target_confirmed": False, "target_confirmed_ms": None, "spoken_ms": 1200 + i * 5} for i in range(5)],
            [{"target_confirmed": False, "target_confirmed_ms": None, "spoken_ms": 900 + i * 5} for i in range(5)],
        )
        unconfirmed_eval = MOD.evaluate_comparison(unconfirmed_records, primary_metric="spoken_ms")
        self.assertEqual(unconfirmed_eval["overall_verdict"], "not_faster")
        self.assertTrue(any("target_not_independently_confirmed" in r for r in unconfirmed_eval["overall_reasons"]))

        noisy_records = make_paired_rounds(
            [{"target_confirmed_ms": v} for v in (1000, 1040, 1080, 1120, 1160)],
            [{"target_confirmed_ms": v} for v in (980, 1020, 1060, 1100, 1140)],
        )
        noisy_eval = MOD.evaluate_comparison(noisy_records)
        self.assertEqual(noisy_eval["overall_verdict"], "not_faster")
        self.assertEqual(noisy_eval["overall_detail"], "no_measurable_difference")
        self.assertTrue(any("within_noise_floor" in r for r in noisy_eval["overall_reasons"]))

        tied_p50_tail_reg = make_paired_rounds(
            [{"target_confirmed_ms": v} for v in (990, 995, 1000, 1005, 1010)],
            [{"target_confirmed_ms": v} for v in (990, 995, 1000, 1005, 2200)],
        )
        tail_eval = MOD.evaluate_comparison(tied_p50_tail_reg)
        self.assertEqual(tail_eval["overall_verdict"], "not_faster")
        self.assertEqual(tail_eval["overall_detail"], "regressed")
        self.assertTrue(any("tail_latency_regressed" in r for r in tail_eval["overall_reasons"]))

        one_verified_each = make_paired_rounds(
            [{"target_confirmed_ms": 1200}] + [{"status": "failed", "target_confirmed": False, "target_confirmed_ms": None, "error": "err"}] * 4,
            [{"target_confirmed_ms": 800}] + [{"status": "failed", "target_confirmed": False, "target_confirmed_ms": None, "error": "err"}] * 4,
        )
        one_ver_eval = MOD.evaluate_comparison(one_verified_each)
        self.assertEqual(one_ver_eval["overall_verdict"], "not_faster")
        self.assertTrue(any("insufficient_verified_runs" in r for r in one_ver_eval["overall_reasons"]))

        zero_baseline = make_paired_rounds(
            [{"target_confirmed_ms": 0, "first_effective_action_ms": 0} for _ in range(5)],
            [{"target_confirmed_ms": 0, "first_effective_action_ms": 0} for _ in range(5)],
        )
        zero_eval = MOD.evaluate_comparison(zero_baseline)
        self.assertEqual(zero_eval["overall_verdict"], "not_faster")

        false_comp_records = make_paired_rounds(
            [{"target_confirmed_ms": 1200 + i * 5} for i in range(5)],
            [{"target_confirmed_ms": 900 + i * 5} for i in range(4)] + [{"target_confirmed_ms": 910, "false_completion_announced": True}],
        )
        fc_eval = MOD.evaluate_comparison(false_comp_records)
        self.assertEqual(fc_eval["overall_verdict"], "not_faster")
        self.assertTrue(any("false_completion_regressed" in r for r in fc_eval["overall_reasons"]))

        dup_records = make_paired_rounds(
            [{"target_confirmed_ms": 1200 + i * 5} for i in range(5)],
            [{"target_confirmed_ms": 900 + i * 5, "duplicate_inputs": 1 if i == 0 else 0} for i in range(5)],
        )
        dup_eval = MOD.evaluate_comparison(dup_records)
        self.assertEqual(dup_eval["overall_verdict"], "not_faster")
        self.assertTrue(any("duplicate_input_regressed" in r for r in dup_eval["overall_reasons"]))

        trunc_records = make_paired_rounds(
            [{"target_confirmed_ms": 1200 + i * 5, "utterance_class": "long_paused_utterance"} for i in range(5)],
            [{"target_confirmed_ms": 900 + i * 5, "utterance_class": "long_paused_utterance", "premature_truncation": (i == 0)} for i in range(5)],
        )
        trunc_eval = MOD.evaluate_comparison(trunc_records)
        self.assertEqual(trunc_eval["overall_verdict"], "not_faster")
        self.assertTrue(any("premature_truncation_regressed" in r for r in trunc_eval["overall_reasons"]))

    def test_phone_direct_and_voice_bridge_judged_separately_and_host_leaks_blocked(self):
        pd = make_paired_rounds(
            [{"sample_id": "pd-cold", "voice_host": "phone_direct", "group": "cold_start", "edge_flags": ["animation_enabled", "no_new_frame"], "target_confirmed_ms": 1200 + i * 5} for i in range(5)],
            [{"sample_id": "pd-cold", "voice_host": "phone_direct", "group": "cold_start", "edge_flags": ["animation_enabled", "no_new_frame"], "target_confirmed_ms": 920 + i * 5} for i in range(5)],
        )
        vb = make_paired_rounds(
            [{"sample_id": "vb-rev", "voice_host": "voice_bridge", "action_host": "mac_tools", "entry_route": "voice_bridge", "observation_source": "mac_mcp_action_readback", "group": "mid_turn_revision", "utterance_class": "long_paused_utterance", "edge_flags": ["target_unchanged"], "mac_tools_ms": 180, "target_confirmed_ms": 1300 + i * 5} for i in range(5)],
            [{"sample_id": "vb-rev", "voice_host": "voice_bridge", "action_host": "mac_tools", "entry_route": "voice_bridge", "observation_source": "mac_mcp_action_readback", "group": "mid_turn_revision", "utterance_class": "long_paused_utterance", "edge_flags": ["target_unchanged"], "mac_tools_ms": 210, "target_confirmed_ms": 1450 + i * 5} for i in range(5)],
        )
        ev = MOD.evaluate_comparison(pd + vb)
        self.assertEqual(ev["hosts"]["phone_direct"]["verdict"], "speedup")
        self.assertEqual(ev["hosts"]["voice_bridge"]["verdict"], "not_faster")
        self.assertEqual(ev["overall_verdict"], "not_faster")

        report = MOD.render_report(pd + vb, ev)
        self.assertIn("| `phone_direct` | `cold_start` | candidate | 5 | 100.0% (5/5) |", report)
        self.assertIn("| `voice_bridge` | `mid_turn_revision` | candidate | 5 | 100.0% (5/5) |", report)
        self.assertIn("| `voice_bridge` | `long_paused_utterance` | baseline | 5 |", report)
        self.assertIn("| `phone_direct` | edge:`no_new_frame` | 5 | 5 |", report)
        self.assertIn("| `voice_bridge` | edge:`target_unchanged` | 5 | 5 |", report)

        leaked = make_paired_rounds(
            [{"voice_host": "phone_direct", "action_host": "phone_local", "target_confirmed_ms": 1200 + i * 5} for i in range(5)],
            [{"voice_host": "phone_direct", "action_host": "mac_tools", "mac_tools_ms": 120, "target_confirmed_ms": 900 + i * 5} for i in range(5)],
        )
        leaked_eval = MOD.evaluate_comparison(leaked)
        self.assertEqual(leaked_eval["overall_verdict"], "not_faster")
        self.assertTrue(any("host_attribution_violation" in r for r in leaked_eval["overall_reasons"]))

        unknown_host = make_paired_rounds(
            [{"voice_host": "none", "target_confirmed_ms": 1200 + i * 5} for i in range(5)],
            [{"voice_host": "none", "target_confirmed_ms": 900 + i * 5} for i in range(5)],
        )
        unknown_eval = MOD.evaluate_comparison(unknown_host)
        self.assertEqual(unknown_eval["overall_verdict"], "not_faster")
        self.assertIn("none", unknown_eval["measured_hosts"])
        self.assertTrue(any("unrecognized_voice_host" in r for r in unknown_eval["overall_reasons"]))

    def test_log_parser_handles_pr799_legacy_truncation_redacted_typing_and_errors(self):
        sample = {"voice_host": "phone_direct", "expected_action_host": "phone_local", "locale": "en", "utterance_class": "short_command"}
        pr799_log = "\n".join([
            "12:00:01.000 [voice-timing] session=1 flow=voice turn=0 t_ms=1000 event=entry_selected entry_route=direct_ephemeral_credential voice_host=phone_direct default_action_host=phone_local transport=realtime model=gpt-realtime-2.1",
            "12:00:02.000 [voice-timing] session=1 flow=voice turn=1 t_ms=2000 event=turn_said entry_route=direct_ephemeral_credential voice_host=phone_direct",
            "12:00:02.080 [voice-timing] session=1 flow=voice turn=1 t_ms=2080 event=turn_heard since_said_ms=80",
            "12:00:02.200 [voice-timing] session=1 flow=voice turn=1 t_ms=2200 event=action_start action=1 tool=do call_id=c1 action_host=phone_local since_said_ms=200",
            '12:00:02.200 [voice] tool do {"actions":[{"type":"…"}]}',
            '12:00:02.210 [voice] tool do {"actions":[{"type":"…"}]}',
            "12:00:02.220 [voice] tool refused during media questions",
            "12:00:02.225 [voice] tool refused during media questions",
            "12:00:02.440 [voice-timing] session=1 flow=voice turn=1 t_ms=2200 event=first_effective_action action=1 tool=do call_id=c1 action_host=phone_local since_said_ms=200",
            "12:00:02.580 [voice-timing] session=1 flow=voice turn=1 t_ms=2580 event=action_end action=1 tool=do call_id=c1 action_host=phone_local observation_source=phone_tree_and_screenshot ok=true tool_ms=380 effective=true confirmed=true since_said_ms=580",
            "12:00:02.580 [voice-timing] session=1 flow=voice turn=1 t_ms=2580 event=target_confirmed action=1 tool=do action_host=phone_local observation_source=phone_tree_and_screenshot since_said_ms=580 since_first_action_ms=380",
            "12:00:02.585 [voice-timing] session=1 flow=voice turn=1 t_ms=2585 event=result_delivered action=1 tool=do call_id=c1 action_host=phone_local observation_source=phone_tree_and_screenshot since_said_ms=585",
            "12:00:02.670 [voice-timing] session=1 flow=voice turn=1 t_ms=2670 event=turn_spoken entry_route=direct_ephemeral_credential voice_host=phone_direct action_host=phone_local observation_source=phone_tree_and_screenshot said_ms=0 heard_ms=80 call_ms=200 first_effective_action_ms=200 tool_done_ms=580 target_confirmed_ms=580 delivered_ms=585 spoken_ms=670 phone_local_ms=380 mac_tools_ms=0 mac_tools_roundtrip_ms=0 calls=do",
        ])
        parsed = MOD.parse_poki_log(pr799_log, entry_mode="bridge_replay", sample=sample)
        self.assertEqual(parsed["timing_source"], "voice-timing")
        self.assertTrue(parsed["target_confirmed"])
        self.assertTrue(parsed["verified_success"])
        self.assertEqual(parsed["duplicate_inputs"], 0)
        self.assertEqual(parsed["milestones_ms"]["first_effective_action_ms"], 200)
        self.assertEqual(parsed["milestones_ms"]["target_confirmed_ms"], 580)
        self.assertEqual(parsed["derived_ms"]["action_to_confirmed_ms"], 380)
        self.assertEqual(parsed["host_ms"]["phone_local_ms"], 380)
        self.assertIsNone(parsed["host_ms"]["mac_tools_ms"])

        paused_sample = dict(sample, utterance_class="long_paused_utterance")
        truncated_log = pr799_log + "\n12:00:03.200 [voice-timing] session=1 flow=voice turn=2 t_ms=3200 event=turn_said entry_route=direct_ephemeral_credential voice_host=phone_direct"
        truncated = MOD.parse_poki_log(truncated_log, entry_mode="bridge_replay", sample=paused_sample)
        self.assertTrue(truncated["premature_truncation"])

        rt_err = MOD.parse_poki_log("12:00:01.000 [voice] realtime error: rate limit exceeded", entry_mode="bridge_replay", sample=sample)
        self.assertEqual(rt_err["status"], "failed")
        self.assertIn("realtime error: rate limit exceeded", rt_err["error"])

        legacy_log = "\n".join([
            "12:01:04.300 [voice] session 1 connection 1: model speech stopped",
            "12:01:05.800 [voice] tool do {}",
            "12:01:09.020 [voice] tool do done | chars=4 elements=0 screen=none",
            "12:01:09.640 [voice] turn: end of speech to spoken result 5340 ms (tool result in 4720 ms)",
            "12:01:18.500 [voice] session 1 connection 1: reply playback stopped (model event)",
        ])
        legacy = MOD.parse_poki_log(legacy_log, entry_mode="rehearsal", sample=sample)
        self.assertEqual(legacy["timing_source"], "legacy-voice-log")
        self.assertEqual(legacy["milestones_ms"]["spoken_ms"], 5340)
        self.assertEqual(legacy["milestones_ms"]["delivered_ms"], 4720)
        self.assertEqual(legacy["host_ms"]["phone_local_ms"], 3220)
        self.assertIsNone(legacy["host_ms"]["mac_tools_ms"])
        self.assertIsNone(legacy["milestones_ms"]["first_effective_action_ms"])
        self.assertIsNone(legacy["milestones_ms"]["target_confirmed_ms"])
        self.assertFalse(legacy["target_confirmed"])
        self.assertFalse(legacy["verified_success"])

    def test_ingest_bridge_honors_timestamps_honest_failures_legacy_reports_and_false_completions(self):
        def base_row(sec: int) -> dict:
            return {
                "at": f"2026-11-27T10:00:{sec:02d}.000Z",
                "n": 14,
                "ok": True,
                "entry_route": "voice_bridge",
                "voice_host": "voice_bridge",
                "action_host": "mac_tools",
                "observation_source": "mac_mcp_action_readback",
                "host_ms": {"phone_local": 0, "mac_tools": 180, "mac_tools_roundtrip": 200},
                "calls": ["open_settings"],
                "reply": "General is open.",
                "ms": {"said": 0, "heard": 50, "call": 150, "first_effective_action": 160, "toolDone": 360, "target_confirmed": 360, "delivered": 370, "spoken": 510},
            }

        interleaved_base = [base_row(1), base_row(4), base_row(5), base_row(8), base_row(9)]
        interleaved_cand = [
            {
                "at": "2026-11-27T10:00:02.000Z",
                "n": 14,
                "ok": True,
                "entry_route": "voice_bridge",
                "voice_host": "voice_bridge",
                "action_host": "mac_tools",
                "observation_source": "none",
                "host_ms": {"phone_local": 0, "mac_tools": 120, "mac_tools_roundtrip": 135},
                "calls": ["open_settings"],
                "reply": "Done, General is open now.",
                "ms": {"said": 0, "heard": 40, "call": 110, "first_effective_action": 120, "toolDone": 255, "delivered": 265, "spoken": 380},
            },
            {
                "at": "2026-11-27T10:00:03.000Z",
                "n": 14,
                "ok": True,
                "entry_route": "voice_bridge",
                "voice_host": "voice_bridge",
                "action_host": "mac_tools",
                "observation_source": "none",
                "host_ms": {"phone_local": 0, "mac_tools": 120, "mac_tools_roundtrip": 135},
                "calls": ["open_settings"],
                "reply": "Sorry, I could not confirm General opened.",
                "ms": {"said": 0, "heard": 40, "call": 110, "first_effective_action": 120, "toolDone": 255, "delivered": 265, "spoken": 380},
            },
            {
                "at": "2026-11-27T10:00:06.000Z",
                "n": 14,
                "ok": False,
                "error": "timeout waiting for turn",
                "entry_route": "voice_bridge",
                "voice_host": "voice_bridge",
                "action_host": "mac_tools",
                "observation_source": "none",
                "host_ms": {"phone_local": 0, "mac_tools": 0, "mac_tools_roundtrip": 0},
                "calls": ["open_settings"],
                "reply": "",
                "ms": {"said": 0},
            },
            dict(base_row(7)),
            dict(base_row(10)),
        ]
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            b_file = root / "base.jsonl"
            c_file = root / "cand.jsonl"
            out_dir = root / "out"
            b_file.write_text("\n".join(json.dumps(r) for r in interleaved_base) + "\n", encoding="utf-8")
            c_file.write_text("\n".join(json.dumps(r) for r in interleaved_cand) + "\n", encoding="utf-8")

            proc = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT_PATH),
                    "ingest-bridge",
                    "--baseline-jsonl", str(b_file),
                    "--candidate-jsonl", str(c_file),
                    "--baseline-commit", "d3f1da1dd",
                    "--candidate-commit", "15f2f3a74",
                    "--changed-variable", "bridge-readback-skip",
                    "--out", str(out_dir),
                ],
                text=True,
                capture_output=True,
                timeout=15,
            )
            self.assertEqual(proc.returncode, 0, proc.stderr)
            summary = json.loads((out_dir / "summary.json").read_text(encoding="utf-8"))
            report = (out_dir / "report.md").read_text(encoding="utf-8")

            seq_base = [base_row(1 + i) for i in range(5)]
            seq_cand = [dict(base_row(20 + i), ms={"said": 0, "first_effective_action": 100, "target_confirmed": 200, "spoken": 300}) for i in range(5)]
            sb_file = root / "seq_base.jsonl"
            sc_file = root / "seq_cand.jsonl"
            seq_out = root / "seq_out"
            sb_file.write_text("\n".join(json.dumps(r) for r in seq_base) + "\n", encoding="utf-8")
            sc_file.write_text("\n".join(json.dumps(r) for r in seq_cand) + "\n", encoding="utf-8")
            seq_proc = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT_PATH),
                    "ingest-bridge",
                    "--baseline-jsonl", str(sb_file),
                    "--candidate-jsonl", str(sc_file),
                    "--baseline-commit", "d3f1da1dd",
                    "--candidate-commit", "15f2f3a74",
                    "--changed-variable", "sequential-check",
                    "--out", str(seq_out),
                ],
                text=True,
                capture_output=True,
                timeout=15,
            )
            self.assertEqual(seq_proc.returncode, 0, seq_proc.stderr)
            seq_summary = json.loads((seq_out / "summary.json").read_text(encoding="utf-8"))

        vb = summary["hosts"]["voice_bridge"]
        self.assertTrue(vb["interleaved"])
        self.assertEqual(vb["verdict"], "not_faster")
        self.assertEqual(vb["candidate"]["false_completion_announcements"], 1)
        self.assertEqual(vb["candidate"]["timeout_count"], 1)
        self.assertIn("timeout waiting for turn", report)

        self.assertEqual(seq_summary["overall_verdict"], "not_faster")
        self.assertFalse(seq_summary["hosts"]["voice_bridge"]["interleaved"])
        self.assertTrue(any("not_interleaved" in r for r in seq_summary["overall_reasons"]))

        legacy_sample = MOD.load_samples_manifest(SAMPLES_PATH)["samples"][0]
        legacy_bridge_row = {"n": 1, "ok": True, "calls": ["do", "do"], "reply": "Done.", "ms": {"heard": 50, "call": 150, "toolDone": 400, "delivered": 420, "spoken": 600}}
        legacy_rec = MOD.record_from_bridge_report(
            legacy_bridge_row,
            side="baseline",
            build_label="base",
            commit_sha="d3f1da1dd",
            changed_variable="timing-only",
            round_num=1,
            order_index=0,
            sample=legacy_sample,
        )
        self.assertFalse(legacy_rec["false_completion_announced"])
        self.assertEqual(legacy_rec["duplicate_inputs"], 0)
        self.assertEqual(legacy_rec["entry_route"], "none")

    def test_alternating_schedule_per_sample_config_drift_and_sample_selection(self):
        samples = [{"id": "s1"}, {"id": "s2"}]
        schedule = MOD.build_alternating_schedule(samples, rounds=4)
        self.assertEqual([item[2] for item in schedule[:4]], ["baseline", "candidate", "baseline", "candidate"])
        self.assertEqual([item[2] for item in schedule[4:8]], ["candidate", "baseline", "candidate", "baseline"])

        drifted = make_paired_rounds(
            [{"target_confirmed_ms": 1200 + i * 5, "config_fingerprint": {"model": "gpt-live-1.1", "vad": "server_vad"}} for i in range(5)],
            [{"target_confirmed_ms": 900 + i * 5, "config_fingerprint": {"model": "gpt-live-1.1", "vad": "semantic_vad"}} for i in range(5)],
        )
        blocked = MOD.evaluate_comparison(drifted)
        self.assertEqual(blocked["overall_verdict"], "not_faster")
        self.assertTrue(any("config_drift" in r for r in blocked["overall_reasons"]))

        allowed = MOD.evaluate_comparison(drifted, allow_config_diff={"vad"})
        self.assertEqual(allowed["overall_verdict"], "speedup", allowed["overall_reasons"])

        swapped: list[dict] = []
        order = 0
        for rnd in range(1, 6):
            sides = ("baseline", "candidate") if rnd % 2 == 1 else ("candidate", "baseline")
            for sid, b_vad, c_vad in (("s1", "server_vad", "semantic_vad"), ("s2", "semantic_vad", "server_vad")):
                for side in sides:
                    swapped.append(
                        make_record(
                            side=side,
                            round_num=rnd,
                            order_index=order,
                            sample_id=sid,
                            target_confirmed_ms=1200 if side == "baseline" else 900,
                            config_fingerprint={"vad": b_vad if side == "baseline" else c_vad},
                        )
                    )
                    order += 1
        swapped_eval = MOD.evaluate_comparison(swapped)
        self.assertTrue(any("config_drift" in r for r in swapped_eval["overall_reasons"]))

        legacy_vs_pr799 = make_paired_rounds(
            [{"target_confirmed_ms": 1200 + i * 5, "config_fingerprint": {"model": "unknown", "transport": "unknown", "locale": "en"}} for i in range(5)],
            [{"target_confirmed_ms": 900 + i * 5, "config_fingerprint": {"model": "gpt-realtime-2.1", "transport": "realtime", "locale": "en"}} for i in range(5)],
        )
        legacy_eval = MOD.evaluate_comparison(legacy_vs_pr799)
        self.assertEqual(legacy_eval["hosts"]["phone_direct"]["config_drifts"], [])

        manifest = MOD.load_samples_manifest(SAMPLES_PATH)
        with self.assertRaises(ValueError):
            MOD.select_samples(manifest, entry_mode="rehearsal", sample_ids="pd-warm-short-calc7-zh")

    def test_simulator_udid_guard_unlinks_stale_log_sanitizes_device_and_retains_timeout(self):
        sim_devices = json.dumps({"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-27-2": [{"udid": "SIM-1111", "name": "Local-Clone-Name", "state": "Booted", "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro"}]}})
        with mock.patch.object(MOD, "simctl", return_value=sim_devices):
            with self.assertRaises(ValueError):
                MOD.lookup_simulator_info("00000000-0000000000000000")

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            app = root / "Poki.app"
            app.mkdir()
            (app / "Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": "nz.zheha.poki", "DTXcodeBuild": "27C5020n", "DTSDKBuild": "24C5037e"}))
            container = root / "container"
            log_file = container / "Library/Caches/poki-log.txt"
            log_file.parent.mkdir(parents=True)
            log_file.write_text("12:00:00.000 [voice] turn: end of speech to spoken result 999 ms (tool result in 500 ms)\n12:00:01.000 [voice] reply playback stopped (model event)\n", encoding="utf-8")

            def fake_simctl(*args, **kwargs):
                if args and args[0] == "get_app_container":
                    return str(container) + "\n"
                return ""

            sample = MOD.load_samples_manifest(SAMPLES_PATH)["samples"][0]
            target = MOD.BuildTarget(side="candidate", label="head", commit="15f2f3a74", app_path=app)
            with mock.patch.object(MOD, "simctl", side_effect=fake_simctl):
                row = MOD.run_simulator_trial(
                    sim_info={
                        "udid": "SIM-1111",
                        "name": "Local-Clone-Name",
                        "state": "Booted",
                        "os_version": "iOS 27 2",
                        "device_type": "com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro",
                    },
                    target=target,
                    changed_variable="timing-instrumentation",
                    entry_mode="rehearsal",
                    round_num=1,
                    order_index=0,
                    sample=sample,
                    timeout_s=0.05,
                    out_dir=root / "out",
                )
            self.assertFalse(log_file.exists(), "stale poki-log.txt must be unlinked before launch")
            self.assertEqual(row["environment"]["device_model"], "iPhone 18 Pro")
            self.assertEqual(row["status"], "timeout")
            self.assertTrue(row["timeout"])
            self.assertFalse(row["verified_success"])
            self.assertIn("timeout", row["error"])


if __name__ == "__main__":
    unittest.main()
