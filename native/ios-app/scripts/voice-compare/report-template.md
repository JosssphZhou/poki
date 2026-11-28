# Voice Speed Comparison Report

## Verdict

- **Overall verdict:** {{OVERALL_VERDICT}}
- **Primary latency metric:** `{{PRIMARY_METRIC}}`
- **Speedup rule:** A candidate is judged `speedup` only when the target is independently confirmed (`target_confirmed`), verified task success rate does not drop, safety/correctness counters (false completion announcements, duplicate inputs, premature truncation) do not regress, and primary latency improves beyond run-to-run variation (`P50` lower, `P95` non-regressing). No unmeasured speedup multipliers are reported.
- **Decision summary:**
{{DECISION_REASONS}}

## Run Metadata and Single-Variable Control

| Field | Value |
| --- | --- |
| Generated (UTC) | {{GENERATED_AT}} |
| Baseline build | {{BASELINE_DESC}} |
| Candidate build | {{CANDIDATE_DESC}} |
| Changed variable | {{CHANGED_VARIABLE}} |
| Entry mode | {{ENTRY_MODE}} |
| Replay entry note | {{REPLAY_NOTE}} |
| Execution order | {{INTERLEAVING_SUMMARY}} |
| Surface and environment | {{ENVIRONMENT_SUMMARY}} |
| Config drift check | {{CONFIG_DRIFT_SUMMARY}} |
| Total runs retained | {{TOTAL_RUNS_SUMMARY}} |

## Per-Host Verdict and Primary Metrics

`phone_direct` and `voice_bridge` are measured and judged separately so Mac bridge latency is never mixed into phone-direct results.

{{PER_HOST_SUMMARY}}

## Milestone Latency Breakdown (ms)

All latencies are measured from `said` (end of speech / recorded audio submission) unless noted (`action_to_confirmed_ms = target_confirmed_ms - first_effective_action_ms`). Missing milestones are reported as `n/a (not measured)`.

{{MILESTONE_BREAKDOWN}}

## Host and Observation Source Attribution

{{ATTRIBUTION_TABLE}}

## Breakdown by Scenario Group

Groups: `cold_start`, `warm_session`, `visual_evidence`, `mid_turn_revision` (kept separate by `voice_host`).

{{GROUP_BREAKDOWN}}

## Breakdown by Utterance Class

Utterance classes: `short_command` vs `long_paused_utterance` (kept separate by `voice_host`).

{{UTTERANCE_BREAKDOWN}}

## Voice Checklist and Retained Edge-Case Samples

Samples with `animation_enabled`, `target_unchanged`, and `no_new_frame` are always retained and never filtered out.

{{EDGE_AND_CHECKLIST_BREAKDOWN}}

## Failures, Timeouts, and Guardrail Violations

Every failed run, timeout, false completion announcement, duplicate input, or premature truncation is retained in raw measurements and listed below.

{{FAILURES_TABLE}}

## Limiter, Verification Surface, and Notes

{{NOTES_SECTION}}
