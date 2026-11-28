//! Progress the shell shows while a long step runs. Every long function takes a [`Reporter`];
//! the UI turns the events into the step list, the CLI prints them.
use serde::Serialize;
use std::sync::Arc;

#[derive(Debug, Clone, Serialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum Progress {
    /// A step began: `id` is stable (`pair`, `sign`, `install`), `title` is for people.
    Step { id: String, title: String },
    /// Part of the current step, 0 to 1, with an optional line.
    Part { id: String, fraction: f64, detail: Option<String> },
    /// A line worth showing under the step (what was found, what was chosen).
    Note { id: String, text: String },
    /// The person has to do something on the phone or in a dialog before the step goes on.
    Waiting { id: String, text: String },
    /// The step is done.
    Done { id: String, detail: Option<String> },
}

/// Where progress goes. Clone it freely; it is an `Arc` inside.
#[derive(Clone)]
pub struct Reporter(Arc<dyn Fn(Progress) + Send + Sync>);

impl Reporter {
    pub fn new(f: impl Fn(Progress) + Send + Sync + 'static) -> Self { Reporter(Arc::new(f)) }
    /// Drops everything; for tests and for calls that have no UI.
    pub fn silent() -> Self { Reporter(Arc::new(|_| {})) }
    /// Prints progress, without repeating the CLI's final install result or handoff.
    pub fn stderr() -> Self {
        Reporter(Arc::new(|p| {
            if let Some(line) = stderr_line(p) { eprintln!("{line}") }
        }))
    }
    pub fn emit(&self, p: Progress) { (self.0)(p) }
    pub fn step(&self, id: &str, title: &str) {
        tracing::info!(step = id, "{title}");
        self.emit(Progress::Step { id: id.into(), title: title.into() })
    }
    pub fn part(&self, id: &str, fraction: f64, detail: Option<String>) { self.emit(Progress::Part { id: id.into(), fraction, detail }) }
    pub fn note(&self, id: &str, text: impl Into<String>) {
        let text = text.into();
        tracing::info!(step = id, "{text}");
        self.emit(Progress::Note { id: id.into(), text })
    }
    pub fn waiting(&self, id: &str, text: impl Into<String>) { self.emit(Progress::Waiting { id: id.into(), text: text.into() }) }
    pub fn done(&self, id: &str, detail: Option<String>) {
        tracing::info!(step = id, detail = detail.as_deref().unwrap_or(""), "done");
        self.emit(Progress::Done { id: id.into(), detail })
    }
}

fn stderr_line(p: Progress) -> Option<String> {
    match p {
        Progress::Step { title, .. } => Some(format!("▸ {title}")),
        Progress::Part { fraction, detail, .. } => detail.map(|d| format!("  {:>3}% {d}", (fraction * 100.0) as u32)),
        Progress::Note { text, .. } => Some(format!("  · {text}")),
        Progress::Waiting { id, .. } if id == "pairing_file" => None,
        Progress::Waiting { text, .. } => Some(format!("  ⏸ {text}")),
        Progress::Done { id, .. } if id == "all" => None,
        Progress::Done { detail, .. } => Some(format!("  ✓ {}", detail.unwrap_or_default())),
    }
}

impl std::fmt::Debug for Reporter {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result { f.write_str("Reporter") }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn terminal_handoff_and_summary_are_left_to_the_cli_result() {
        let handoff = Progress::Waiting { id: "pairing_file".into(), text: "Scan the code".into() };
        let finished = Progress::Done { id: "all".into(), detail: Some("Poki is installed".into()) };
        assert!(stderr_line(handoff).is_none());
        assert!(stderr_line(finished).is_none());

        let trust = Progress::Waiting { id: "pair".into(), text: "Tap Trust".into() };
        assert_eq!(stderr_line(trust).as_deref(), Some("  ⏸ Tap Trust"));
    }
}
