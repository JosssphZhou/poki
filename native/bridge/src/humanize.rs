//! Human-like timing and trajectory shaping for HID input.
//!
//! Shapes injected input after measured human movement instead of fixed
//! schedules: minimum-jerk position profiles for reaches (Flash & Hogan 1985),
//! endpoint scatter that scales with movement speed (Schmidt et al. 1979),
//! log-normal press and inter-key intervals, curved swipes with smooth drift,
//! and per-frame deadline jitter so event cadence is never uniform.
//!
//! Every plan function returns the exact legacy values when disabled, so
//! callers keep one code path and tests stay deterministic.

use serde_json::json;

const TAP_PRESS_MEDIAN_MS: f64 = 85.0;
const TAP_PRESS_SIGMA: f64 = 0.30;
const TAP_PRESS_MIN_MS: u64 = 55;
const TAP_PRESS_MAX_MS: u64 = 220;
/// Touch endpoint scatter: ~2 px at 3x (54 HID units per px), clamped to 8 px.
const TAP_START_SIGMA_UNITS: f64 = 110.0;
const TAP_START_MAX_UNITS: f64 = 430.0;
/// Fingertip micro-drift while a tap contact is held down.
const TAP_DRIFT_MIN_UNITS: f64 = 10.0;
const TAP_DRIFT_MAX_UNITS: f64 = 90.0;
const DOUBLE_TAP_GAP_MEDIAN_MS: f64 = 110.0;
const DOUBLE_TAP_GAP_SIGMA: f64 = 0.30;
const DOUBLE_TAP_GAP_MIN_MS: u64 = 70;
const DOUBLE_TAP_GAP_MAX_MS: u64 = 240;

const DRAG_TOTAL_MIN_FACTOR: f64 = 0.88;
const DRAG_TOTAL_MAX_FACTOR: f64 = 1.18;
const DRAG_HOLD_MIN_FACTOR: f64 = 0.9;
const DRAG_HOLD_MAX_FACTOR: f64 = 1.15;
const DRAG_END_HOLD_MIN_FACTOR: f64 = 0.85;
const DRAG_END_HOLD_MAX_FACTOR: f64 = 1.3;
const DRAG_START_SIGMA_UNITS: f64 = 80.0;
const DRAG_FRAME_DT_MIN_FACTOR: f64 = 0.65;
const DRAG_FRAME_DT_MAX_FACTOR: f64 = 1.35;
/// Slow curved path: lateral arc of 0.4%-2% of distance plus layered drift.
const DRAG_ARC_MIN_FRACTION: f64 = 0.004;
const DRAG_ARC_MAX_FRACTION: f64 = 0.02;
const DRAG_MICRO_SIGMA_UNITS: f64 = 9.0;
/// Schmidt's linear speed-accuracy tradeoff: scatter grows with peak speed.
const END_SCATTER_BASE_UNITS: f64 = 30.0;
const END_SCATTER_PER_SPEED_UNITS: f64 = 25.0;
const END_SCATTER_MAX_UNITS: f64 = 500.0;

const PINCH_TOTAL_MIN_FACTOR: f64 = 0.9;
const PINCH_TOTAL_MAX_FACTOR: f64 = 1.15;
const PINCH_NOISE_FRACTION: f64 = 0.01;
const PINCH_CONTACT_SIGMA_UNITS: f64 = 20.0;

const KEY_HOLD_MEDIAN_MS: f64 = 90.0;
const KEY_HOLD_SIGMA: f64 = 0.35;
const KEY_HOLD_MIN_MS: u64 = 55;
const KEY_HOLD_MAX_MS: u64 = 200;
const KEY_GAP_MEDIAN_MS: f64 = 130.0;
const KEY_GAP_SIGMA: f64 = 0.40;
const KEY_GAP_MIN_MS: u64 = 60;
const KEY_GAP_MAX_MS: u64 = 420;
const MODIFIER_LEAD_MIN_MS: u64 = 30;
const MODIFIER_LEAD_MAX_MS: u64 = 70;
const MODIFIER_TAIL_MIN_MS: u64 = 40;
const MODIFIER_TAIL_MAX_MS: u64 = 120;
const BUTTON_INTERVAL_MIN_FACTOR: f64 = 0.8;
const BUTTON_INTERVAL_MAX_FACTOR: f64 = 1.35;
const BUTTON_HOLD_MIN_FACTOR: f64 = 0.85;
const BUTTON_HOLD_MAX_FACTOR: f64 = 1.25;

/// Shared RNG and debug sink for one request. `poki-native` handles a single
/// request per process, so configuration comes from the environment once.
pub(crate) struct Humanize {
    enabled: bool,
    state: u64,
    spare_normal: Option<f64>,
    debug_path: Option<String>,
}

impl Humanize {
    pub(crate) fn off() -> Self {
        Self { enabled: false, state: 0, spare_normal: None, debug_path: None }
    }

    /// Fixed-seed instance for tests that assert on sampled values.
    pub(crate) fn seeded(seed: u64) -> Self {
        Self { enabled: true, state: seed, spare_normal: None, debug_path: None }
    }

    /// Enabled unless POKI_HUMANIZE=off|0. POKI_HUMANIZE_SEED pins the RNG for
    /// reproducible runs; POKI_HUMANIZE_DEBUG=<path> appends plan summaries.
    pub(crate) fn from_env() -> Self {
        let enabled = !matches!(
            std::env::var("POKI_HUMANIZE").as_deref(),
            Ok("off") | Ok("0")
        );
        let state = std::env::var("POKI_HUMANIZE_SEED")
            .ok()
            .and_then(|seed| seed.parse::<u64>().ok())
            .unwrap_or_else(|| {
                let nanos = std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .map(|d| d.as_nanos() as u64)
                    .unwrap_or(0x9E3779B97F4A7C15);
                nanos ^ (std::process::id() as u64).rotate_left(32)
            });
        let debug_path = std::env::var("POKI_HUMANIZE_DEBUG").ok().filter(|p| !p.is_empty());
        Self { enabled, state, spare_normal: None, debug_path }
    }

    pub(crate) fn enabled(&self) -> bool {
        self.enabled
    }

    fn next_u64(&mut self) -> u64 {
        // SplitMix64: small, dependency-free, well distributed.
        self.state = self.state.wrapping_add(0x9E3779B97F4A7C15);
        let mut z = self.state;
        z = (z ^ (z >> 30)).wrapping_mul(0xBF58476D1CE4E5B9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94D049BB133111EB);
        z ^ (z >> 31)
    }

    fn uniform(&mut self) -> f64 {
        (self.next_u64() >> 11) as f64 * (1.0 / 9_007_199_254_740_992.0)
    }

    fn uniform_range(&mut self, min: f64, max: f64) -> f64 {
        min + (max - min) * self.uniform()
    }

    fn normal(&mut self) -> f64 {
        if let Some(spare) = self.spare_normal.take() {
            return spare;
        }
        // Box-Muller; u1 must be > 0 to avoid log(0).
        let u1 = self.uniform().max(f64::MIN_POSITIVE);
        let u2 = self.uniform();
        let magnitude = (-2.0 * u1.ln()).sqrt();
        let angle = std::f64::consts::TAU * u2;
        self.spare_normal = Some(magnitude * (angle * 0.5).sin());
        magnitude * angle.cos()
    }

    fn jitter_point(&mut self, x: u16, y: u16, sigma: f64, max_offset: f64) -> (u16, u16) {
        if !self.enabled {
            return (x, y);
        }
        let dx = (self.normal() * sigma).clamp(-max_offset, max_offset);
        let dy = (self.normal() * sigma).clamp(-max_offset, max_offset);
        (clamp_coord(x as f64 + dx), clamp_coord(y as f64 + dy))
    }

    fn lognormal_ms(&mut self, median: f64, sigma: f64, min_ms: u64, max_ms: u64) -> u64 {
        let ms = median * (sigma * self.normal()).exp();
        ms.clamp(min_ms as f64, max_ms as f64).round() as u64
    }

    fn record(&self, summary: serde_json::Value) {
        if let Some(path) = &self.debug_path {
            if let Ok(mut file) = std::fs::OpenOptions::new().create(true).append(true).open(path) {
                use std::io::Write as _;
                let _ = writeln!(file, "{summary}");
            }
        }
    }
}

fn clamp_coord(value: f64) -> u16 {
    value.round().clamp(0.0, 65535.0) as u16
}

fn scale_duration(h: &mut Humanize, requested_ms: u64, min: f64, max: f64) -> u64 {
    (requested_ms as f64 * h.uniform_range(min, max))
        .round()
        .clamp(1.0, 60000.0) as u64
}

pub(crate) struct TapPlan {
    pub contact: (u16, u16),
    pub release: (u16, u16),
    pub press_ms: u64,
}

/// A tap or long press: scatter the contact point around the target, hold for
/// a sampled duration, and drift a little before releasing.
pub(crate) fn tap_plan(h: &mut Humanize, x: u16, y: u16, requested_ms: u64, long_press: bool) -> TapPlan {
    if !h.enabled {
        return TapPlan { contact: (x, y), release: (x, y), press_ms: requested_ms };
    }
    let contact = h.jitter_point(x, y, TAP_START_SIGMA_UNITS, TAP_START_MAX_UNITS);
    let drift_angle = h.uniform() * std::f64::consts::TAU;
    let drift = h.uniform_range(TAP_DRIFT_MIN_UNITS, TAP_DRIFT_MAX_UNITS);
    let release = clamp_coord(contact.0 as f64 + drift * drift_angle.cos());
    let release = (release, clamp_coord(contact.1 as f64 + drift * drift_angle.sin()));
    let press_ms = if long_press {
        scale_duration(h, requested_ms, 0.92, 1.10)
    } else {
        h.lognormal_ms(TAP_PRESS_MEDIAN_MS, TAP_PRESS_SIGMA, TAP_PRESS_MIN_MS, TAP_PRESS_MAX_MS)
    };
    h.record(json!({
        "op": if long_press { "long_press" } else { "tap" },
        "request": [x, y, requested_ms],
        "contact": [contact.0, contact.1],
        "release": [release.0, release.1],
        "press_ms": press_ms,
    }));
    TapPlan { contact, release, press_ms }
}

pub(crate) struct DragPlan {
    pub contact: (u16, u16),
    pub release: (u16, u16),
    pub hold_ms: u64,
    pub end_hold_ms: u64,
    /// Contact frames as (x, y, milliseconds after the movement starts).
    pub frames: Vec<(u16, u16, u64)>,
}

/// A drag or scroll: minimum-jerk timing along the chord, a slow lateral arc,
/// smooth drift and per-frame micro jitter, jittered frame deadlines, and
/// endpoint scatter that grows with peak speed.
pub(crate) fn drag_plan(
    h: &mut Humanize,
    x1: u16,
    y1: u16,
    x2: u16,
    y2: u16,
    duration_ms: u64,
    hold_ms: u64,
    end_hold_ms: u64,
) -> DragPlan {
    if !h.enabled {
        return DragPlan {
            contact: (x1, y1),
            release: (x2, y2),
            hold_ms,
            end_hold_ms,
            frames: Vec::new(),
        };
    }
    let total_ms = scale_duration(h, duration_ms, DRAG_TOTAL_MIN_FACTOR, DRAG_TOTAL_MAX_FACTOR);
    let hold = scale_duration(h, hold_ms, DRAG_HOLD_MIN_FACTOR, DRAG_HOLD_MAX_FACTOR);
    let end_hold = scale_duration(h, end_hold_ms, DRAG_END_HOLD_MIN_FACTOR, DRAG_END_HOLD_MAX_FACTOR);
    let contact = h.jitter_point(x1, y1, DRAG_START_SIGMA_UNITS, TAP_START_MAX_UNITS);

    let dx = f64::from(x2) - f64::from(x1);
    let dy = f64::from(y2) - f64::from(y1);
    let distance = dx.hypot(dy).max(1.0);
    let steps = total_ms.div_ceil(16).max(1) as usize;
    // Per-frame cadence jitter, then renormalized so the last deadline stays total_ms.
    let mut deadlines = Vec::with_capacity(steps);
    let mut sum = 0.0;
    for _ in 0..steps {
        let dt = total_ms as f64 / steps as f64
            * h.uniform_range(DRAG_FRAME_DT_MIN_FACTOR, DRAG_FRAME_DT_MAX_FACTOR);
        sum += dt;
        deadlines.push(dt);
    }
    let mut elapsed = 0.0;
    for dt in &mut deadlines {
        *dt *= total_ms as f64 / sum;
        elapsed += *dt;
        let rounded = elapsed.round().max(1.0) as u64;
        *dt = rounded.min(total_ms) as f64;
    }
    // Restore strict monotonicity after rounding (defensive; per-frame gaps
    // are >= ~10 ms so rounding cannot collapse them).
    for index in 1..deadlines.len() {
        if deadlines[index] <= deadlines[index - 1] {
            deadlines[index] = deadlines[index - 1] + 1.0;
        }
    }

    let arc = distance * h.uniform_range(DRAG_ARC_MIN_FRACTION, DRAG_ARC_MAX_FRACTION)
        * if h.uniform() < 0.5 { -1.0 } else { 1.0 };
    let noise_slow_amplitude = distance * h.uniform_range(0.002, 0.005);
    let noise_fast_amplitude = distance * h.uniform_range(0.001, 0.003);
    let noise_slow_freq = h.uniform_range(0.5, 1.8);
    let noise_fast_freq = h.uniform_range(0.8, 2.6);
    let noise_slow_phase = h.uniform() * std::f64::consts::TAU;
    let noise_fast_phase = h.uniform() * std::f64::consts::TAU;
    // Perpendicular direction of travel.
    let (perp_x, perp_y) = (-dy / distance, dx / distance);
    // Peak speed of the minimum-jerk profile is 1.875 * distance / duration.
    let peak_speed = 1.875 * distance / (total_ms as f64 / 1000.0);
    let end_sigma = (END_SCATTER_BASE_UNITS + END_SCATTER_PER_SPEED_UNITS * peak_speed)
        .min(END_SCATTER_MAX_UNITS);

    let mut frames = Vec::with_capacity(steps);
    for (index, &at_ms) in deadlines.iter().enumerate() {
        let t = (index + 1) as f64 / steps as f64;
        // Minimum-jerk position profile: 10t^3 - 15t^4 + 6t^5.
        let s = 10.0 * t * t * t - 15.0 * t * t * t * t + 6.0 * t * t * t * t * t;
        let lateral = arc * (std::f64::consts::PI * t).sin()
            + noise_slow_amplitude * (std::f64::consts::TAU * noise_slow_freq * t + noise_slow_phase).sin()
            + noise_fast_amplitude * (std::f64::consts::TAU * noise_fast_freq * t + noise_fast_phase).sin();
        let jitter_x = h.normal() * DRAG_MICRO_SIGMA_UNITS;
        let jitter_y = h.normal() * DRAG_MICRO_SIGMA_UNITS;
        let x = x1 as f64 + dx * s + perp_x * lateral + jitter_x;
        let y = y1 as f64 + dy * s + perp_y * lateral + jitter_y;
        frames.push((clamp_coord(x), clamp_coord(y), at_ms.round() as u64));
    }
    // Release lands near the final frame with speed-scaled scatter.
    let (last_x, last_y, _) = frames.last().copied().unwrap_or((x2, y2, total_ms));
    let release = h.jitter_point(last_x, last_y, end_sigma, END_SCATTER_MAX_UNITS);

    h.record(json!({
        "op": "drag",
        "request": [x1, y1, x2, y2, duration_ms],
        "contact": [contact.0, contact.1],
        "release": [release.0, release.1],
        "hold_ms": hold,
        "end_hold_ms": end_hold,
        "total_ms": total_ms,
        "frames": frames.len(),
        "end_sigma": end_sigma.round(),
    }));
    DragPlan { contact, release, hold_ms: hold, end_hold_ms: end_hold, frames }
}

pub(crate) struct PinchPlan {
    /// (distance, milliseconds after the gesture starts) per contact frame.
    pub frames: Vec<(f64, u64)>,
}

/// A pinch: minimum-jerk distance progression with smooth noise and jittered
/// frame deadlines; finger positions keep the requested angle and center.
pub(crate) fn pinch_plan(
    h: &mut Humanize,
    start_distance: f64,
    end_distance: f64,
    duration_ms: u64,
) -> PinchPlan {
    if !h.enabled {
        return PinchPlan { frames: Vec::new() };
    }
    let total_ms = scale_duration(h, duration_ms, PINCH_TOTAL_MIN_FACTOR, PINCH_TOTAL_MAX_FACTOR);
    let steps = total_ms.div_ceil(16).max(1) as usize;
    let mut deadlines = Vec::with_capacity(steps);
    let mut sum = 0.0;
    for _ in 0..steps {
        let dt = total_ms as f64 / steps as f64
            * h.uniform_range(DRAG_FRAME_DT_MIN_FACTOR, DRAG_FRAME_DT_MAX_FACTOR);
        sum += dt;
        deadlines.push(dt);
    }
    let mut elapsed = 0.0;
    for dt in &mut deadlines {
        *dt *= total_ms as f64 / sum;
        elapsed += *dt;
        *dt = elapsed.round().max(1.0).min(total_ms as f64);
    }
    let noise_amplitude = (end_distance - start_distance).abs() * PINCH_NOISE_FRACTION
        + start_distance.abs() * PINCH_NOISE_FRACTION * 0.5;
    let noise_freq = h.uniform_range(0.5, 1.8);
    let noise_phase = h.uniform() * std::f64::consts::TAU;
    let mut frames = Vec::with_capacity(steps);
    for (index, &at_ms) in deadlines.iter().enumerate() {
        let t = (index + 1) as f64 / steps as f64;
        let s = 10.0 * t * t * t - 15.0 * t * t * t * t + 6.0 * t * t * t * t * t;
        let noise = noise_amplitude
            * (std::f64::consts::TAU * noise_freq * t + noise_phase).sin();
        let distance = start_distance + (end_distance - start_distance) * s + noise;
        frames.push((distance, at_ms.round() as u64));
    }
    h.record(json!({
        "op": "pinch",
        "request": [start_distance, end_distance, duration_ms],
        "total_ms": total_ms,
        "frames": frames.len(),
    }));
    PinchPlan { frames }
}

/// Sub-pixel nudge for one contact finger of a pinch frame.
pub(crate) fn pinch_contact_jitter(h: &mut Humanize, x: u16, y: u16) -> (u16, u16) {
    if !h.enabled {
        return (x, y);
    }
    h.jitter_point(x, y, PINCH_CONTACT_SIGMA_UNITS, PINCH_CONTACT_SIGMA_UNITS * 3.0)
}

pub(crate) fn key_hold_ms(h: &mut Humanize) -> u64 {
    if !h.enabled { 50 } else { h.lognormal_ms(KEY_HOLD_MEDIAN_MS, KEY_HOLD_SIGMA, KEY_HOLD_MIN_MS, KEY_HOLD_MAX_MS) }
}

pub(crate) fn key_gap_ms(h: &mut Humanize) -> u64 {
    if !h.enabled { 50 } else { h.lognormal_ms(KEY_GAP_MEDIAN_MS, KEY_GAP_SIGMA, KEY_GAP_MIN_MS, KEY_GAP_MAX_MS) }
}

pub(crate) fn modifier_lead_ms(h: &mut Humanize) -> u64 {
    if !h.enabled { 50 } else { h.uniform_range(MODIFIER_LEAD_MIN_MS as f64, MODIFIER_LEAD_MAX_MS as f64).round() as u64 }
}

pub(crate) fn modifier_tail_ms(h: &mut Humanize) -> u64 {
    if !h.enabled { 50 } else { h.uniform_range(MODIFIER_TAIL_MIN_MS as f64, MODIFIER_TAIL_MAX_MS as f64).round() as u64 }
}

pub(crate) fn double_tap_gap_ms(h: &mut Humanize) -> u64 {
    if !h.enabled {
        80
    } else {
        h.lognormal_ms(DOUBLE_TAP_GAP_MEDIAN_MS, DOUBLE_TAP_GAP_SIGMA, DOUBLE_TAP_GAP_MIN_MS, DOUBLE_TAP_GAP_MAX_MS)
    }
}

pub(crate) fn button_interval_ms(h: &mut Humanize, requested_ms: u64) -> u64 {
    if !h.enabled {
        requested_ms
    } else {
        scale_duration(h, requested_ms, BUTTON_INTERVAL_MIN_FACTOR, BUTTON_INTERVAL_MAX_FACTOR)
    }
}

pub(crate) fn button_hold_ms(h: &mut Humanize, requested_ms: u64) -> u64 {
    if !h.enabled {
        requested_ms
    } else {
        scale_duration(h, requested_ms, BUTTON_HOLD_MIN_FACTOR, BUTTON_HOLD_MAX_FACTOR)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn assert_between(value: u64, min: u64, max: u64, label: &str) {
        assert!(
            (min..=max).contains(&value),
            "{label}: {value} not in [{min}, {max}]"
        );
    }

    #[test]
    fn disabled_plan_is_exact_legacy_passthrough() {
        let mut h = Humanize::off();
        let tap = tap_plan(&mut h, 100, 200, 50, false);
        assert_eq!((tap.contact, tap.release, tap.press_ms), ((100, 200), (100, 200), 50));
        let drag = drag_plan(&mut h, 1, 2, 3, 4, 500, 20, 30);
        assert_eq!(
            (drag.contact, drag.release, drag.hold_ms, drag.end_hold_ms, drag.frames.is_empty()),
            ((1, 2), (3, 4), 20, 30, true)
        );
        let pinch = pinch_plan(&mut h, 100.0, 500.0, 500);
        assert_eq!(pinch.frames.is_empty(), true);
        assert_eq!(key_hold_ms(&mut h), 50);
        assert_eq!(double_tap_gap_ms(&mut h), 80);
    }

    #[test]
    fn seeded_generation_is_deterministic() {
        let plan_a = {
            let mut h = Humanize::seeded(7);
            tap_plan(&mut h, 5000, 5000, 50, false)
        };
        let plan_b = {
            let mut h = Humanize::seeded(7);
            tap_plan(&mut h, 5000, 5000, 50, false)
        };
        assert_eq!(plan_a.contact, plan_b.contact);
        assert_eq!(plan_a.release, plan_b.release);
        assert_eq!(plan_a.press_ms, plan_b.press_ms);
    }

    #[test]
    fn tap_press_ms_stays_in_human_range_and_scatter_stays_bounded() {
        let mut h = Humanize::seeded(11);
        for _ in 0..200 {
            let plan = tap_plan(&mut h, 32768, 32768, 50, false);
            assert_between(plan.press_ms, TAP_PRESS_MIN_MS, TAP_PRESS_MAX_MS, "tap press_ms");
            let offset = (f64::from(plan.contact.0) - 32768.0).hypot(f64::from(plan.contact.1) - 32768.0);
            assert!(offset <= TAP_START_MAX_UNITS * 2.0f64.sqrt(), "scatter {offset} too large");
            let drift = (f64::from(plan.release.0) - f64::from(plan.contact.0))
                .hypot(f64::from(plan.release.1) - f64::from(plan.contact.1));
            assert!(drift <= TAP_DRIFT_MAX_UNITS + 2.0, "drift {drift} too large");
        }
        // A long press keeps the requested magnitude but is never exact.
        let mut seen_varied = false;
        let mut durations = std::collections::HashSet::new();
        for _ in 0..20 {
            let plan = tap_plan(&mut h, 100, 100, 1000, true);
            assert_between(plan.press_ms, 900, 1120, "long press_ms");
            durations.insert(plan.press_ms);
            seen_varied |= durations.len() > 1;
        }
        assert!(seen_varied, "long press durations never vary");
    }

    #[test]
    fn drag_frames_follow_s_curve_with_monotonic_deadlines() {
        let mut h = Humanize::seeded(23);
        let plan = drag_plan(&mut h, 1000, 5000, 20000, 5000, 800, 20, 30);
        assert!(plan.frames.len() >= 40, "too few frames: {}", plan.frames.len());
        // Deadlines are strictly increasing and end near the jittered total.
        let mut last = 0;
        for &(_, _, at_ms) in &plan.frames {
            assert!(at_ms > last, "deadline {at_ms} not after {last}");
            last = at_ms;
        }
        assert_between(last, 650, 1000, "drag total");
        // Progress crosses the midpoint near t=0.5 (minimum-jerk is symmetric).
        let half_frames = plan
            .frames
            .iter()
            .filter(|&&(x, _, _)| x >= 10000 && x <= 11000)
            .count();
        assert!(half_frames > 0, "path never crosses the midpoint");
        // All coordinates stay on screen.
        for &(x, y, _) in &plan.frames {
            assert!(x <= 65535 && y <= 65535);
        }
        // Release stays near the requested endpoint (scatter bounded).
        let release_offset =
            (f64::from(plan.release.0) - 20000.0).hypot(f64::from(plan.release.1) - 5000.0);
        assert!(release_offset <= END_SCATTER_MAX_UNITS + DRAG_MICRO_SIGMA_UNITS * 3.0);
    }

    #[test]
    fn drag_s_curve_is_not_linear_in_time() {
        // A linear ramp at t=0.25 covers 25% of distance; minimum-jerk covers
        // ~10.4% (10*0.25^3 - 15*0.25^4 + 6*0.25^5 = 0.1035). Assert the
        // sampled early progress stays clearly below the linear share.
        let mut h = Humanize::seeded(31);
        let plan = drag_plan(&mut h, 0, 5000, 30000, 5000, 800, 0, 0);
        let quarter_index = plan.frames.len() / 4;
        let (x, _, _) = plan.frames[quarter_index];
        let progress = f64::from(x) / 30000.0;
        assert!(
            progress < 0.20,
            "early progress {progress} looks linear, not minimum-jerk"
        );
    }

    #[test]
    fn pinch_plan_produces_monotonic_deadlines_and_bounded_noise() {
        let mut h = Humanize::seeded(41);
        let plan = pinch_plan(&mut h, 400.0, 1600.0, 500);
        let mut last = 0;
        let mut min_distance = f64::INFINITY;
        let mut max_distance = f64::NEG_INFINITY;
        for &(distance, at_ms) in &plan.frames {
            assert!(at_ms > last, "pinch deadline {at_ms} not after {last}");
            last = at_ms;
            min_distance = min_distance.min(distance);
            max_distance = max_distance.max(distance);
        }
        assert_between(last, 430, 600, "pinch total");
        // Noise stays within a small band around the start-end span.
        assert!(min_distance >= 350.0, "pinch distance {min_distance} too low");
        assert!(max_distance <= 1650.0, "pinch distance {max_distance} too high");
    }

    #[test]
    fn key_timing_stays_in_human_ranges() {
        let mut h = Humanize::seeded(53);
        for _ in 0..100 {
            assert_between(key_hold_ms(&mut h), KEY_HOLD_MIN_MS, KEY_HOLD_MAX_MS, "key hold");
            assert_between(key_gap_ms(&mut h), KEY_GAP_MIN_MS, KEY_GAP_MAX_MS, "key gap");
            assert_between(
                double_tap_gap_ms(&mut h),
                DOUBLE_TAP_GAP_MIN_MS,
                DOUBLE_TAP_GAP_MAX_MS,
                "double tap gap",
            );
        }
        assert_between(
            button_interval_ms(&mut h, 120),
            (120.0 * BUTTON_INTERVAL_MIN_FACTOR) as u64,
            (120.0 * BUTTON_INTERVAL_MAX_FACTOR).ceil() as u64,
            "button interval",
        );
    }

    #[test]
    fn debug_dump_writes_json_line() {
        let dir = std::env::temp_dir().join(format!("poki-humanize-test-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("debug.jsonl");
        let mut h = Humanize { enabled: true, state: 99, spare_normal: None, debug_path: Some(path.to_string_lossy().into_owned()) };
        let _ = tap_plan(&mut h, 100, 100, 50, false);
        let content = std::fs::read_to_string(&path).unwrap();
        assert!(content.contains("\"op\":\"tap\""), "missing tap record: {content}");
        std::fs::remove_dir_all(&dir).unwrap();
    }
}

