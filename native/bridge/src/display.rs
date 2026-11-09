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
    /// Clockwise rotation of the panel's content from its native orientation, in degrees.
    pub rotation: u16,
}

/// Maps a point normalized to the screen as the user sees it (0..=65535 on both axes) onto the
/// touchscreen's native axes. The digitizer reports in the panel's native orientation, so a panel
/// showing rotated content needs the inverse rotation. Calibrated on a two-panel iPhone whose inner
/// panel reported `rot90` in landscape: unrotated, a tap aimed at screen (150, 621) of 951 x 669
/// points landed near (67, 106), which fits screen = (1 - native_y, native_x) and no other turn.
pub fn to_panel(rotation: u16, x: u16, y: u16) -> (u16, u16) {
    match rotation {
        90 => (y, u16::MAX - x),
        180 => (u16::MAX - x, u16::MAX - y),
        270 => (u16::MAX - y, x),
        _ => (x, y),
    }
}

/// The active integrated display, or `None` when the phone does not advertise CoreDevice device
/// information. Callers then keep the single-display defaults: display 1, the main touchscreen HID
/// service, the DVT screenshot and the cached AX subscription.
pub async fn active(adapter: &mut AdapterHandle, rsd: &RsdHandshake) -> Result<Option<Display>> {
    // Boxed so the query does not enlarge every input and read future that awaits it; inline, the
    // tap path overflowed the 2 MiB stack of a debug test thread.
    Box::pin(query(adapter, rsd)).await
}

async fn query(adapter: &mut AdapterHandle, rsd: &RsdHandshake) -> Result<Option<Display>> {
    let Some(service) = rsd.services.get("com.apple.coredevice.deviceinfo") else {
        return Ok(None);
    };
    let port = service.port;
    let mut client = CoreDeviceServiceClient::new(adapter.connect(port).await?).await?;
    let info = client
        .invoke_with_plist(
            "com.apple.coredevice.feature.getdisplayinfo",
            plist::Dictionary::new(),
        )
        .await?;
    select(&serde_json::to_value(info)?).map(Some)
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
    let rotation = match d["currentOrientation"].as_str() {
        None | Some("rot0") => 0,
        Some("rot90") => 90,
        Some("rot180") => 180,
        Some("rot270") => 270,
        Some(other) => return Err(format!("Unknown display orientation {other}").into()),
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
        rotation,
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
        assert_eq!(d.rotation, 0);
    }
    #[test]
    fn reads_panel_rotation_and_refuses_unknown_values() {
        let mut info = fixture();
        info["displays"][1]["currentOrientation"] = json!("rot90");
        assert_eq!(select(&info).unwrap().rotation, 90);
        info["displays"][1]["currentOrientation"] = json!("sideways");
        assert!(select(&info).is_err());
    }
    #[test]
    fn maps_screen_points_onto_native_touch_axes() {
        let m = u16::MAX;
        assert_eq!(to_panel(0, 100, 200), (100, 200));
        // rot90 landscape: screen top-left is the panel's top-right, screen bottom-left its top-left.
        assert_eq!(to_panel(90, 0, 0), (0, m));
        assert_eq!(to_panel(90, 0, m), (m, m));
        assert_eq!(to_panel(90, m, 0), (0, 0));
        assert_eq!(to_panel(180, 0, 0), (m, m));
        assert_eq!(to_panel(270, 0, 0), (m, 0));
        for r in [90, 180, 270] {
            let (mut x, mut y) = (1234, 54321);
            for _ in 0..4 {
                (x, y) = to_panel(r, x, y);
            }
            assert_eq!((x, y), (1234, 54321), "rotation {r} applied a full turn is the identity");
        }
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
