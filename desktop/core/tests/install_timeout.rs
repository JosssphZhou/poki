use poki_setup_core::{device::{install::install_ipa, Link, Phone}, Progress, Reporter};
use std::{net::TcpListener, sync::{Arc, Mutex}, time::Duration};
use tokio::io::AsyncReadExt;

fn main() {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    listener.set_nonblocking(true).unwrap();
    // This test has no libtest harness or runtime threads yet, so changing the environment is safe.
    unsafe { std::env::set_var("USBMUXD_SOCKET_ADDRESS", listener.local_addr().unwrap().to_string()) };
    tokio::runtime::Builder::new_current_thread().enable_all().build().unwrap().block_on(async {
        let listener = tokio::net::TcpListener::from_std(listener).unwrap();
        for upgrade in [true, false] {
            stalled_install_explains_how_to_retry(&listener, upgrade).await;
        }
    });
}

async fn stalled_install_explains_how_to_retry(listener: &tokio::net::TcpListener, upgrade: bool) {
    let ipa = tempfile::NamedTempFile::new().unwrap();
    let phone = Phone { udid: "test-phone".into(), link: Link::Usb, mux_id: Some(1) };
    let events = Arc::new(Mutex::new(Vec::new()));
    let collected = events.clone();
    let reporter = Reporter::new(move |event| collected.lock().unwrap().push(event));
    let install = tokio::spawn(async move { install_ipa(&phone, ipa.path(), upgrade, &reporter).await });

    let mut connection = tokio::time::timeout(Duration::from_secs(10), async {
        let (mut connection, _) = listener.accept().await.unwrap();
        let mut request = [0; 16];
        connection.read_exact(&mut request).await.unwrap();
        let length = u32::from_le_bytes(request[..4].try_into().unwrap()) as usize;
        assert!((16..65536).contains(&length));
        connection.read_exact(&mut vec![0; length - 16]).await.unwrap();
        connection
    }).await.expect("the installer must reach the isolated device service");

    assert!(events.lock().unwrap().iter().any(|event| matches!(event,
        Progress::Note { id, text } if id == "install"
            && text.contains("close Poki on your iPhone")
            && text.contains("chats and settings will be kept")
    )), "explain that installation closes Poki and keeps chats and settings before contacting the phone");

    tokio::time::pause();
    tokio::time::advance(Duration::from_secs(600)).await;
    let error = tokio::time::timeout(Duration::from_secs(1), install).await
        .expect("installation must stop waiting after ten minutes").unwrap().unwrap_err().to_string();
    tokio::time::resume();
    println!("upgrade={upgrade}: {error}");

    assert!(error.contains("Close Poki") && error.contains("try again"),
        "a stalled install must explain how to retry: {error}");
    let events = events.lock().unwrap();
    assert!(events.iter().any(|event| matches!(event,
        Progress::Note { id, text } if id == "install" && text.contains("Close Poki") && text.contains("app switcher")
    )), "show how to close Poki while installation is waiting");
    assert!(!events.iter().any(|event| matches!(event,
        Progress::Done { id, .. } if id == "install"
    )), "a timed-out install must not report success");
    let mut byte = [0];
    assert_eq!(connection.read(&mut byte).await.unwrap(), 0, "drop the stalled connection on timeout");
    println!("stalled_install_explains_how_to_retry passed (upgrade={upgrade})");
}
