# Voice Speed Comparison Report

## Verdict

- **Overall verdict:** **NOT FASTER (inconclusive)**
- **Primary latency metric:** `target_confirmed_ms`
- **Speedup rule:** A candidate is judged `speedup` only when the target is independently confirmed (`target_confirmed`), verified task success rate does not drop, safety/correctness counters (false completion announcements, duplicate inputs, premature truncation) do not regress, and primary latency improves beyond run-to-run variation (`P50` lower, `P95` non-regressing). No unmeasured speedup multipliers are reported.
- **Decision summary:**
  - [phone_direct] target_not_independently_confirmed: baseline confirmed=0/15, candidate confirmed=0/15
  - [phone_direct] missing_primary_latency: target_confirmed_ms has baseline n=0, candidate n=0 on verified runs

## Run Metadata and Single-Variable Control

| Field | Value |
| --- | --- |
| Generated (UTC) | 2026-11-27T09:47:01Z |
| Baseline build | `merge-base` @ `d3f1da1dd` |
| Candidate build | `pr799` @ `15f2f3a74` |
| Changed variable | voice-turn-timing-instrumentation |
| Entry mode | rehearsal |
| Replay entry note | Silent simulator rehearsal (`-pokiTalk talk -pokiTalkRehearsal 1|lost`) used while recorded-audio replay fixtures (`-pokiVoiceLink` + `bin/voice-bridge.mjs --test-dir`) are pending. Sample IDs and `uNN.24k.pcm` indices share the same replay manifest. |
| Execution order | Alternating across 5 rounds (1..5), interleaved=True |
| Surface and environment | surface=ios_simulator; device=iPhone 18 Pro; os=iOS 27 2; xcode=27C5020n; cpus=30; host_load_1m=120.12..233.62 |
| Config drift check | PASS (no unintended config drift) |
| Total runs retained | 30 total (baseline=15, candidate=15, failed=10, timeout=0; 0 dropped) |

## Per-Host Verdict and Primary Metrics

`phone_direct` and `voice_bridge` are measured and judged separately so Mac bridge latency is never mixed into phone-direct results.

### Host: `phone_direct` -> **NOT FASTER (inconclusive)**

| Metric | Baseline | Candidate | Delta (Candidate - Baseline) |
| --- | --- | --- | --- |
| Runs (retained) | 15 (failed=5, timeout=0) | 15 (failed=5, timeout=0) | +0 |
| Verified task success rate | 0.0% (0/15) | 0.0% (0/15) | +0.0 pp |
| Independent target confirmation | 0.0% (0/15) | 0.0% (0/15) | +0.0 pp |
| Raw completion rate (status=ok) | 66.7% (10/15) | 66.7% (10/15) | +0.0 pp |
| Premature truncation rate | 0.0% (0/15) | 0.0% (0/15) | +0.0 pp |
| Duplicate input count | 0 | 0 | +0 |
| False completion announcements | 0 | 0 | +0 |
| Model roundtrips (P50 / P95 / total) | 2.0 / 2.0 / 30 | 2.0 / 2.0 / 30 | +0 total |
| Primary `target_confirmed_ms` (verified runs) | n/a (not measured) | n/a (not measured) | n/a (not measured) |
| `spoken_ms` (all completed turns) | P50 5348.0 / P95 5352.9 [5325.0..5355.0] (n=15) | P50 5344.0 / P95 5365.9 [5325.0..5368.0] (n=15) | -4.0 ms (-0.1%) |
| Run-to-run variation floor (`noise_floor_ms`) | n/a | n/a | n/a ms |

Reasons:
- target_not_independently_confirmed: baseline confirmed=0/15, candidate confirmed=0/15
- missing_primary_latency: target_confirmed_ms has baseline n=0, candidate n=0 on verified runs

### Host: `voice_bridge`

0 runs collected (not measured in this run; pending recorded-audio replay or device execution).

## Milestone Latency Breakdown (ms)

All latencies are measured from `said` (end of speech / recorded audio submission) unless noted (`action_to_confirmed_ms = target_confirmed_ms - first_effective_action_ms`). Missing milestones are reported as `n/a (not measured)`.

| Voice Host | Milestone | Baseline (ms) | Candidate (ms) | P50 Delta |
| --- | --- | --- | --- | --- |
| `phone_direct` | `said_ms` | P50 0.0 / P95 0.0 [0.0..0.0] (n=15) | P50 0.0 / P95 0.0 [0.0..0.0] (n=15) | +0.0 ms |
| `phone_direct` | `heard_ms` | n/a (not measured) | P50 308.0 / P95 314.3 [301.0..315.0] (n=15) | n/a (not measured) |
| `phone_direct` | `call_ms` | P50 1524.0 / P95 1536.5 [1516.0..1540.0] (n=15) | P50 1522.0 / P95 1533.3 [1512.0..1534.0] (n=15) | -2.0 ms (-0.1%) |
| `phone_direct` | `first_effective_action_ms` | n/a (not measured) | n/a (not measured) | n/a (not measured) |
| `phone_direct` | `tool_done_ms` | P50 4733.0 / P95 4748.7 [4728.0..4762.0] (n=15) | P50 4726.0 / P95 4742.7 [4718.0..4749.0] (n=15) | -7.0 ms (-0.1%) |
| `phone_direct` | `target_confirmed_ms` | n/a (not measured) | n/a (not measured) | n/a (not measured) |
| `phone_direct` | `action_to_confirmed_ms` | n/a (not measured) | n/a (not measured) | n/a (not measured) |
| `phone_direct` | `delivered_ms` | P50 4732.0 / P95 4748.0 [4727.0..4762.0] (n=15) | P50 4726.0 / P95 4743.4 [4718.0..4749.0] (n=15) | -6.0 ms (-0.1%) |
| `phone_direct` | `spoken_ms` | P50 5348.0 / P95 5352.9 [5325.0..5355.0] (n=15) | P50 5344.0 / P95 5365.9 [5325.0..5368.0] (n=15) | -4.0 ms (-0.1%) |
| `phone_direct` | `phone_local_ms` | P50 3208.0 / P95 3224.6 [3201.0..3240.0] (n=15) | P50 3206.0 / P95 3211.2 [3201.0..3214.0] (n=15) | -2.0 ms (-0.1%) |
| `phone_direct` | `mac_tools_ms` | n/a (not measured) | n/a (not measured) | n/a (not measured) |
| `phone_direct` | `mac_tools_roundtrip_ms` | n/a (not measured) | n/a (not measured) | n/a (not measured) |
| `phone_direct` | `wall_ms` | P50 25479.0 / P95 27352.7 [24752.0..27597.0] (n=15) | P50 25156.0 / P95 27125.2 [24785.0..28332.0] (n=15) | -323.0 ms (-1.3%) |

## Host and Observation Source Attribution

| Side | Entry Route | Voice Host | Action Host | Observation Source | Runs |
| --- | --- | --- | --- | --- | ---: |
| baseline | `rehearsal` | `phone_direct` | `phone_local` | `none` | 15 |
| candidate | `rehearsal` | `phone_direct` | `phone_local` | `phone_tool_output` | 15 |

## Breakdown by Scenario Group

Groups: `cold_start`, `warm_session`, `visual_evidence`, `mid_turn_revision` (kept separate by `voice_host`).

| Voice Host | Slice | Side | Runs | Verified Success | Confirmed | Premature Trunc. | Dup Inputs | False Comp. | Roundtrips (P50/P95) | Primary P50 / P95 (ms) | Spoken P50 / P95 (ms) |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- | --- |
| `phone_direct` | `cold_start` | baseline | 15 | 0.0% (0/15) | 0.0% (0/15) | 0.0% | 0 | 0 | 2.0 / 2.0 | n/a (not measured) | 5348.0 / 5352.9 |
| `phone_direct` | `cold_start` | candidate | 15 | 0.0% (0/15) | 0.0% (0/15) | 0.0% | 0 | 0 | 2.0 / 2.0 | n/a (not measured) | 5344.0 / 5365.9 |
| `phone_direct` | `warm_session` | baseline / candidate | 0 | n/a | n/a | n/a | 0 | 0 | n/a | n/a (not measured) | n/a (not measured) |
| `phone_direct` | `visual_evidence` | baseline / candidate | 0 | n/a | n/a | n/a | 0 | 0 | n/a | n/a (not measured) | n/a (not measured) |
| `phone_direct` | `mid_turn_revision` | baseline / candidate | 0 | n/a | n/a | n/a | 0 | 0 | n/a | n/a (not measured) | n/a (not measured) |
| `voice_bridge` | `cold_start` | baseline / candidate | 0 | n/a | n/a | n/a | 0 | 0 | n/a | n/a (not measured) | n/a (not measured) |
| `voice_bridge` | `warm_session` | baseline / candidate | 0 | n/a | n/a | n/a | 0 | 0 | n/a | n/a (not measured) | n/a (not measured) |
| `voice_bridge` | `visual_evidence` | baseline / candidate | 0 | n/a | n/a | n/a | 0 | 0 | n/a | n/a (not measured) | n/a (not measured) |
| `voice_bridge` | `mid_turn_revision` | baseline / candidate | 0 | n/a | n/a | n/a | 0 | 0 | n/a | n/a (not measured) | n/a (not measured) |

## Breakdown by Utterance Class

Utterance classes: `short_command` vs `long_paused_utterance` (kept separate by `voice_host`).

| Voice Host | Slice | Side | Runs | Verified Success | Confirmed | Premature Trunc. | Dup Inputs | False Comp. | Roundtrips (P50/P95) | Primary P50 / P95 (ms) | Spoken P50 / P95 (ms) |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- | --- |
| `phone_direct` | `short_command` | baseline | 15 | 0.0% (0/15) | 0.0% (0/15) | 0.0% | 0 | 0 | 2.0 / 2.0 | n/a (not measured) | 5348.0 / 5352.9 |
| `phone_direct` | `short_command` | candidate | 15 | 0.0% (0/15) | 0.0% (0/15) | 0.0% | 0 | 0 | 2.0 / 2.0 | n/a (not measured) | 5344.0 / 5365.9 |
| `phone_direct` | `long_paused_utterance` | baseline / candidate | 0 | n/a | n/a | n/a | 0 | 0 | n/a | n/a (not measured) | n/a (not measured) |
| `voice_bridge` | `short_command` | baseline / candidate | 0 | n/a | n/a | n/a | 0 | 0 | n/a | n/a (not measured) | n/a (not measured) |
| `voice_bridge` | `long_paused_utterance` | baseline / candidate | 0 | n/a | n/a | n/a | 0 | 0 | n/a | n/a (not measured) | n/a (not measured) |

## Voice Checklist and Retained Edge-Case Samples

Samples with `animation_enabled`, `target_unchanged`, and `no_new_frame` are always retained and never filtered out.

| Voice Host | Category / Edge Flag | Baseline Runs Retained | Candidate Runs Retained | Verified Success (B / C) | Failed or Timeout (B / C) |
| --- | --- | ---: | ---: | --- | --- |
| `phone_direct` | edge:`animation_enabled` | 15 | 15 | 0/15 vs 0/15 | 5 vs 5 |
| `phone_direct` | edge:`target_unchanged` | 15 | 15 | 0/15 vs 0/15 | 5 vs 5 |
| `phone_direct` | edge:`no_new_frame` | 15 | 15 | 0/15 vs 0/15 | 5 vs 5 |
| `phone_direct` | checklist:`stop` | 0 | 0 | 0/0 vs 0/0 | 0 vs 0 |
| `phone_direct` | checklist:`duplicate_utterance` | 0 | 0 | 0/0 vs 0/0 | 0 vs 0 |
| `phone_direct` | checklist:`disconnect_reconnect` | 5 | 5 | 0/5 vs 0/5 | 5 vs 5 |
| `phone_direct` | checklist:`tool_failure` | 0 | 0 | 0/0 vs 0/0 | 0 vs 0 |
| `phone_direct` | checklist:`continuation` | 0 | 0 | 0/0 vs 0/0 | 0 vs 0 |
| `phone_direct` | checklist:`permission_denied` | 0 | 0 | 0/0 vs 0/0 | 0 vs 0 |
| `phone_direct` | checklist:`core_speed` | 10 | 10 | 0/10 vs 0/10 | 0 vs 0 |

## Failures, Timeouts, and Guardrail Violations

Every failed run, timeout, false completion announcement, duplicate input, or premature truncation is retained in raw measurements and listed below.

| Run ID | Side | Round | Sample | Voice Host | Group | Status | Timeout | Target Confirmed | False Comp. | Dup Inputs | Premature Trunc. | Error |
| --- | --- | ---: | --- | --- | --- | --- | --- | --- | --- | ---: | --- | --- |
| `r01_004_baseline_pd-disconnect-rehearsal-en` | baseline | 1 | `pd-disconnect-rehearsal-en` | `phone_direct` | `cold_start` | `failed` | false | false | false | 0 | false | connection lost: rehearsal |
| `r01_005_candidate_pd-disconnect-rehearsal-en` | candidate | 1 | `pd-disconnect-rehearsal-en` | `phone_direct` | `cold_start` | `failed` | false | false | false | 0 | false | connection lost: rehearsal |
| `r02_010_candidate_pd-disconnect-rehearsal-en` | candidate | 2 | `pd-disconnect-rehearsal-en` | `phone_direct` | `cold_start` | `failed` | false | false | false | 0 | false | connection lost: rehearsal |
| `r02_011_baseline_pd-disconnect-rehearsal-en` | baseline | 2 | `pd-disconnect-rehearsal-en` | `phone_direct` | `cold_start` | `failed` | false | false | false | 0 | false | connection lost: rehearsal |
| `r03_016_baseline_pd-disconnect-rehearsal-en` | baseline | 3 | `pd-disconnect-rehearsal-en` | `phone_direct` | `cold_start` | `failed` | false | false | false | 0 | false | connection lost: rehearsal |
| `r03_017_candidate_pd-disconnect-rehearsal-en` | candidate | 3 | `pd-disconnect-rehearsal-en` | `phone_direct` | `cold_start` | `failed` | false | false | false | 0 | false | connection lost: rehearsal |
| `r04_022_candidate_pd-disconnect-rehearsal-en` | candidate | 4 | `pd-disconnect-rehearsal-en` | `phone_direct` | `cold_start` | `failed` | false | false | false | 0 | false | connection lost: rehearsal |
| `r04_023_baseline_pd-disconnect-rehearsal-en` | baseline | 4 | `pd-disconnect-rehearsal-en` | `phone_direct` | `cold_start` | `failed` | false | false | false | 0 | false | connection lost: rehearsal |
| `r05_028_baseline_pd-disconnect-rehearsal-en` | baseline | 5 | `pd-disconnect-rehearsal-en` | `phone_direct` | `cold_start` | `failed` | false | false | false | 0 | false | connection lost: rehearsal |
| `r05_029_candidate_pd-disconnect-rehearsal-en` | candidate | 5 | `pd-disconnect-rehearsal-en` | `phone_direct` | `cold_start` | `failed` | false | false | false | 0 | false | connection lost: rehearsal |

## Limiter, Verification Surface, and Notes

- **Limiter:** Synthetic 3.2 s TalkRehearsal.step() sleep and scripted event offsets on iOS Simulator (no live model TTFT, microphone capture, or independent screen readback; host load recorded per trial).
- **Simulator rehearsal scope:** `-pokiTalk talk -pokiTalkRehearsal 1|lost` uses a fixed 3.2 s synthetic tool wait returning `"done"` without live model TTFT, real microphone audio, or independent screen readback. It verifies the comparison harness, log parsing, host attribution, failure retention, and absence of regression, and is NOT verified on a physical iPhone.
- **Verification surface:** Not verified on a physical iPhone unless `surface=physical_iphone` is shown in Run Metadata.
