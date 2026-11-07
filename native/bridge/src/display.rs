use super::Result;
use idevice::{
    core_device::CoreDeviceServiceClient, rsd::RsdHandshake, tcp::handle::AdapterHandle,
};
use serde_json::Value;

pub struct Display {
    pub id: i64,
    pub unique_id: String,
    pub primary: bool,
    pub multiple_integrated: bool,
    pub width: f64,
    pub height: f64,
    pub orientation: Option<u64>,
}

pub async fn active(adapter: &mut AdapterHandle, rsd: &RsdHandshake) -> Result<Display> {
    let port = rsd
        .services
        .get("com.apple.coredevice.deviceinfo")
        .ok_or("CoreDevice display information is unavailable")?
        .port;
    let mut client = CoreDeviceServiceClient::new(adapter.connect(port).await?).await?;
    let info = client
        .invoke_with_plist(
            "com.apple.coredevice.feature.getdisplayinfo",
            plist::Dictionary::new(),
        )
        .await?;
    select(&serde_json::to_value(info)?)
}

fn select(info: &Value) -> Result<Display> {
    let displays = info["displays"]
        .as_array()
        .ok_or("Display list is missing")?;
    let integrated: Vec<_> = displays.iter().filter(|d| d["external"] == false).collect();
    let active: Vec<_> = integrated
        .iter()
        .copied()
        .filter(|d| d["active"] == true)
        .collect();
    if active.len() != 1 {
        return Err("Exactly one active integrated display is required".into());
    }
    let d = active[0];
    let id = d["displayId"]
        .as_i64()
        .filter(|id| *id > 0)
        .ok_or("Invalid display ID")?;
    let unique_id = d["uniqueId"]
        .as_str()
        .filter(|id| !id.is_empty())
        .ok_or("Display unique ID is missing")?
        .to_owned();
    let scale = d["pointScale"]
        .as_f64()
        .filter(|v| v.is_finite() && *v > 0.0 && *v <= 5.0)
        .ok_or("Invalid display scale")?;
    let dimension = |index: usize| -> Result<f64> {
        Ok(d["bounds"][1][index]
            .as_f64()
            .filter(|v| v.is_finite() && *v > 0.0)
            .ok_or("Invalid active display bounds")?
            / scale)
    };
    let orientation = match info["orientation"]["currentDeviceOrientation"].as_str() {
        Some("portrait") => Some(1),
        Some("portraitUpsideDown") => Some(2),
        Some("landscapeLeft") => Some(3),
        Some("landscapeRight") => Some(4),
        _ => None,
    };
    Ok(Display {
        id,
        unique_id,
        primary: d["primary"]
            .as_bool()
            .ok_or("Display primary flag is missing")?,
        multiple_integrated: integrated.len() > 1,
        width: dimension(0)?,
        height: dimension(1)?,
        orientation,
    })
}

pub fn touch_surface(
    display: &Display,
    surfaces: &[idevice::core_device::hid::HidSurface],
) -> Result<u64> {
    let product = format!("CoreDevice touchscreen({})", display.unique_id);
    let touch: Vec<_> = surfaces
        .iter()
        .filter(|s| s.primary_usage_page == Some(13) && s.primary_usage == Some(4))
        .collect();
    let matched: Vec<_> = touch
        .iter()
        .copied()
        .filter(|s| s.product.as_deref() == Some(product.as_str()))
        .collect();
    if matched.len() == 1 {
        return Ok(matched[0].service_id);
    }
    if matched.is_empty()
        && !display.multiple_integrated
        && touch.len() == 1
        && touch[0].product.as_deref() == Some("CoreDevice touchscreen(nil)")
    {
        return Ok(touch[0].service_id);
    }
    Err("Cannot identify exactly one touchscreen for the active display".into())
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    fn fixture() -> Value {
        json!({"displays":[
            {"displayId":1,"uniqueId":"outer","external":false,"active":false,"primary":true,"pointScale":3,"bounds":[[0,0],[1398,2034]]},
            {"displayId":2,"uniqueId":"inner","external":false,"active":true,"primary":false,"pointScale":3,"bounds":[[0,0],[2007,2853]]},
            {"displayId":3,"external":true,"active":true}],"orientation":{"currentDeviceOrientation":"portrait"}})
    }
    #[test]
    fn selects_active_panel_and_uses_current_bounds() {
        let d = select(&fixture()).unwrap();
        assert_eq!(
            (d.id, d.unique_id.as_str(), d.primary, d.multiple_integrated),
            (2, "inner", false, true)
        );
        assert_eq!((d.width, d.height, d.orientation), (669.0, 951.0, Some(1)));
    }
    #[test]
    fn refuses_missing_ambiguous_or_uncalibrated_panels() {
        for (field, value) in [
            ("pointScale", json!(0)),
            ("uniqueId", json!("")),
            ("bounds", json!([[0, 0], [0, 0]])),
        ] {
            let mut info = fixture();
            info["displays"][1][field] = value;
            assert!(select(&info).is_err());
        }
        let mut info = fixture();
        info["displays"][0]["active"] = json!(true);
        assert!(select(&info).is_err());
        info["displays"][0]["active"] = json!(false);
        info["displays"][1]["active"] = json!(false);
        assert!(select(&info).is_err());
    }
    #[test]
    fn selects_touchscreen_by_unique_id_and_refuses_ambiguity() {
        use idevice::core_device::hid::HidSurface;
        let surface = |id, name: &str| HidSurface {
            service_id: id,
            product: Some(format!("CoreDevice touchscreen({name})")),
            primary_usage_page: Some(13),
            primary_usage: Some(4),
        };
        let display = select(&fixture()).unwrap();
        let mut surfaces = vec![surface(257, "outer"), surface(258, "inner")];
        assert_eq!(touch_surface(&display, &surfaces).unwrap(), 258);
        surfaces.push(surface(259, "inner"));
        assert!(touch_surface(&display, &surfaces).is_err());
        assert!(touch_surface(&display, &[surface(257, "outer")]).is_err());
    }
}
