//! The supervisor against a phone that misbehaves at the pairing port: it answers nothing, hangs
//! up at once, or flaps. The supervisor must keep trying with bounded backoff, never wedge, react to
//! restart at once, and go idle on stop even while an attempt is stuck. Each peer listens on
//! an OS-assigned port on localhost. Tests take turns configuring the launcher’s process-wide port.

use idevice::remote_pairing::RpPairingFile;
use poki_launcher::{Config, Launcher, poki_set_remote_pairing_port};
use serde_json::{Value, json};
use std::{
    io::Write,
    net::TcpListener,
    path::PathBuf,
    sync::{Arc, Mutex, MutexGuard},
    time::{Duration, Instant},
};

static PORT_LOCK: Mutex<()> = Mutex::new(());

struct TestPort {
    _guard: MutexGuard<'static, ()>,
}

impl Drop for TestPort {
    fn drop(&mut self) {
        poki_set_remote_pairing_port(0);
    }
}

fn loopback_listener() -> (TestPort, TcpListener) {
    let guard = PORT_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    let listener = TcpListener::bind(("127.0.0.1", 0)).unwrap();
    poki_set_remote_pairing_port(listener.local_addr().unwrap().port());
    (TestPort { _guard: guard }, listener)
}

fn pairing_file(name: &str) -> PathBuf {
    let path = std::env::temp_dir().join(format!("poki-soak-{}-{name}.plist", std::process::id()));
    std::fs::write(&path, RpPairingFile::generate("Poki").to_bytes()).unwrap();
    path
}

type Events = Arc<Mutex<Vec<(Instant, Value)>>>;

fn launcher(name: &str) -> (Arc<Launcher>, Events) {
    let config: Config = serde_json::from_value(json!({"pairing_file": pairing_file(name), "device_address": "127.0.0.1"})).unwrap();
    let events: Events = Arc::new(Mutex::new(Vec::new()));
    let sink = events.clone();
    let launcher = Arc::new(Launcher::new(config, Box::new(move |e| sink.lock().unwrap().push((Instant::now(), e)))));
    (launcher, events)
}

fn states(events: &Events) -> Vec<String> {
    events.lock().unwrap().iter().map(|(_, e)| e["state"].as_str().unwrap_or("").to_string()).collect()
}

fn wait_for(events: &Events, seconds: u64, check: impl Fn(&[String]) -> bool) -> bool {
    let until = Instant::now() + Duration::from_secs(seconds);
    while Instant::now() < until {
        if check(&states(events)) {
            return true;
        }
        std::thread::sleep(Duration::from_millis(20));
    }
    false
}

/// A peer that accepts and then says nothing, holding every connection open.
fn silent_peer(listener: TcpListener) -> Arc<Mutex<Vec<std::net::TcpStream>>> {
    let held = Arc::new(Mutex::new(Vec::new()));
    let keep = held.clone();
    std::thread::spawn(move || {
        for stream in listener.incoming().flatten() {
            keep.lock().unwrap().push(stream);
        }
    });
    held
}

/// A peer that accepts and hangs up at once, or sends garbage first.
fn rude_peer(listener: TcpListener) {
    std::thread::spawn(move || {
        for (n, stream) in listener.incoming().flatten().enumerate() {
            let mut stream = stream;
            if n % 2 == 1 {
                let _ = stream.write_all(b"\x00\x00\x00\x10not rppairing!!!");
            }
            drop(stream);
        }
    });
}

#[test]
fn stop_goes_idle_at_once_even_while_an_attempt_hangs() {
    let (_port, listener) = loopback_listener();
    let held = silent_peer(listener);
    let (launcher, events) = launcher("silent");
    launcher.clone().start();
    assert!(wait_for(&events, 5, |s| s.iter().any(|x| x == "pairing")), "{:?}", states(&events));
    assert!(wait_for(&events, 5, |_| !held.lock().unwrap().is_empty()), "the peer saw no connection");
    std::thread::sleep(Duration::from_millis(500));
    let asked = Instant::now();
    launcher.stop();
    assert_eq!(launcher.status()["state"], "idle");
    assert!(asked.elapsed() < Duration::from_millis(200), "stop took {:?}", asked.elapsed());
    // After stop, nothing more is attempted (the thread ends; its runner cleanup is bounded at 6 s and
    // reports what it did as one more "idle" status).
    std::thread::sleep(Duration::from_secs(7));
    let after: Vec<String> = events.lock().unwrap().iter().filter(|(t, e)| *t > asked + Duration::from_millis(50) && e["state"] != "idle").map(|(_, e)| e["state"].to_string()).collect();
    assert!(after.is_empty(), "events after stop: {after:?}");
}

#[test]
fn a_silent_phone_times_out_and_is_tried_again() {
    let (_port, listener) = loopback_listener();
    let _held = silent_peer(listener);
    let (launcher, events) = launcher("slow");
    launcher.clone().start();
    // The open is capped at 20 s, then the attempt fails with a fix and the next one starts.
    assert!(wait_for(&events, 30, |s| s.iter().any(|x| x == "waiting_network" || x == "failed")), "{:?}", states(&events));
    let failure = events.lock().unwrap().iter().rev().find(|(_, e)| e["state"] == "waiting_network" || e["state"] == "failed").unwrap().1.clone();
    assert!(failure["fix"].is_string(), "no fix: {failure}");
    assert!(wait_for(&events, 5, |s| s.iter().filter(|x| *x == "connecting").count() >= 2), "no second attempt: {:?}", states(&events));
    launcher.stop();
}

#[test]
fn a_rude_phone_backs_off_and_restart_cuts_the_wait_short() {
    let (_port, listener) = loopback_listener();
    rude_peer(listener);
    let (launcher, events) = launcher("rude");
    launcher.clone().start();
    std::thread::sleep(Duration::from_secs(8));
    let attempts = states(&events).iter().filter(|x| *x == "connecting").count();
    // Backoff 1, 2, 4 s: about four attempts in 8 s, never a busy loop.
    assert!((2..=6).contains(&attempts), "{attempts} attempts in 8 s: {:?}", states(&events));
    let before = attempts;
    let asked = Instant::now();
    launcher.restart();
    assert!(wait_for(&events, 2, |s| s.iter().filter(|x| *x == "connecting").count() > before), "restart did not start an attempt");
    assert!(asked.elapsed() < Duration::from_millis(1500));
    launcher.stop();
    assert_eq!(launcher.status()["state"], "idle");
    // Start again after stop: it runs again.
    launcher.clone().start();
    let count = states(&events).iter().filter(|x| *x == "connecting").count();
    assert!(wait_for(&events, 3, |s| s.iter().filter(|x| *x == "connecting").count() > count), "no attempt after start again");
    launcher.stop();
}
