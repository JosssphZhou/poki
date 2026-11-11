use crate::{Config, device::{Device, Pairing, Failure}};
use idevice::springboardservices::SpringBoardServicesClient;
use serde_json::{Value, json};
use std::time::Duration;

pub async fn list(config: Config) -> Result<Value, Failure> {
    let mut pairing = Pairing::read(&config.pairing_file, config.host_name.as_deref())?;
    let mut device = Device::open(config.device_address, &mut pairing, Duration::from_secs(4)).await?;
    let mut proxy = device.installation_proxy().await?;
    let installed = proxy.get_apps(None, None).await?;
    let mut apps = installed.into_iter().map(|(bundle, info)| {
        let fields = info.as_dictionary();
        let names: Vec<&str> = ["CFBundleDisplayName", "CFBundleName"].into_iter()
            .filter_map(|key| fields?.get(key)?.as_string()).filter(|name| !name.is_empty()).collect();
        json!({"bundleID": bundle, "displayName": names.first().copied().unwrap_or(&bundle), "aliases": names})
    }).collect::<Vec<_>>();
    let icons = tokio::time::timeout(Duration::from_secs(2), async {
        let mut springboard: SpringBoardServicesClient = device.connect().await?;
        springboard.get_icon_state(Some("2")).await
    }).await;
    if let Ok(Ok(icons)) = icons {
        localized_names(&mut apps, &icons);
    } else {
        let known: std::collections::BTreeMap<String, String> = serde_json::from_str(include_str!("../../../src/data/app-names.json"))?;
        for (name, bundle) in known {
            if let Some(app) = apps.iter_mut().find(|app| app["bundleID"] == bundle) {
                app["aliases"].as_array_mut().unwrap().push(json!(name));
            }
        }
    }
    apps.sort_by(|a, b| a["bundleID"].as_str().cmp(&b["bundleID"].as_str()));
    Ok(json!({"apps": apps}))
}

fn localized_names(apps: &mut [Value], icons: &plist::Value) {
    match icons {
        plist::Value::Array(items) => for item in items { localized_names(apps, item); },
        plist::Value::Dictionary(fields) => {
            let bundle = fields.get("bundleIdentifier").or_else(|| fields.get("displayIdentifier")).and_then(plist::Value::as_string);
            let name = fields.get("displayName").and_then(plist::Value::as_string);
            if let (Some(bundle), Some(name)) = (bundle, name)
                && !name.is_empty()
                && let Some(app) = apps.iter_mut().find(|app| app["bundleID"] == bundle) {
                app["displayName"] = json!(name);
                app["aliases"].as_array_mut().unwrap().push(json!(name));
            }
            for value in fields.values() { localized_names(apps, value); }
        }
        _ => {}
    }
}
