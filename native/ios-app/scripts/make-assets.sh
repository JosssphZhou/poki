#!/bin/bash
# Makes the asset catalogs (macOS, needs swift): the app icon from docs/images/poki-app-icon.png (the bear
# on the front page's sky, full-bleed, no margin; iOS applies its own corner mask), from
# docs/images/poki-icon.png the Bear image for the app and the Live Activity, and Poki's poses for both. They are generated, not
# checked in, so the source images stay the only copies. Run before xcodegen.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
ICON="$ROOT/docs/images/poki-icon.png"
APPICON="$ROOT/docs/images/poki-app-icon.png"
COMPOSE="$ROOT/native/ios-runner/branding/compose.swift"
BLUE="#2084FD"
meta='{"info":{"version":1,"author":"poki"}}'

catalog() { rm -rf "$1"; mkdir -p "$1"; echo "$meta" > "$1/Contents.json"; }
bear() {
  mkdir -p "$1/Bear.imageset"
  swift "$COMPOSE" "$ICON" "$1/Bear.imageset/bear@3x.png" 360 1.0
  echo '{"images":[{"filename":"bear@3x.png","idiom":"universal","scale":"3x"}],"info":{"version":1,"author":"poki"}}' > "$1/Bear.imageset/Contents.json"
}

APP="$HERE/Poki/Assets.xcassets"
catalog "$APP"
mkdir -p "$APP/AppIcon.appiconset"
# The colour only makes the PNG opaque, which an app icon must be: the picture covers all of it.
swift "$COMPOSE" "$APPICON" "$APP/AppIcon.appiconset/icon-1024.png" 1024 1.0 "$BLUE"
echo '{"images":[{"filename":"icon-1024.png","idiom":"universal","platform":"ios","size":"1024x1024"}],"info":{"version":1,"author":"poki"}}' > "$APP/AppIcon.appiconset/Contents.json"
mkdir -p "$APP/AccentColor.colorset"
echo '{"colors":[{"idiom":"universal","color":{"color-space":"srgb","components":{"red":"0x11","green":"0x11","blue":"0x10","alpha":"1.000"}}},{"idiom":"universal","appearances":[{"appearance":"luminosity","value":"dark"}],"color":{"color-space":"srgb","components":{"red":"0xF4","green":"0xF4","blue":"0xF1","alpha":"1.000"}}}],"info":{"version":1,"author":"poki"}}' > "$APP/AccentColor.colorset/Contents.json"
# The launch screen's ground: the page's own paper (Paper.page), so the first frame does not flash.
mkdir -p "$APP/Paper.colorset"
echo '{"colors":[{"idiom":"universal","color":{"color-space":"srgb","components":{"red":"0xFA","green":"0xFA","blue":"0xF9","alpha":"1.000"}}},{"idiom":"universal","appearances":[{"appearance":"luminosity","value":"dark"}],"color":{"color-space":"srgb","components":{"red":"0x0C","green":"0x0C","blue":"0x0D","alpha":"1.000"}}}],"info":{"version":1,"author":"poki"}}' > "$APP/Paper.colorset/Contents.json"
bear "$APP"
# Provider logos (Poki/ProviderIcons, see its README) as vector template images.
logos() {
  for svg in "$HERE"/Poki/ProviderIcons/*.svg; do
    name="Provider-$(basename "$svg" .svg)"
    mkdir -p "$1/$name.imageset"
    cp "$svg" "$1/$name.imageset/logo.svg"
    echo '{"images":[{"filename":"logo.svg","idiom":"universal"}],"info":{"version":1,"author":"poki"},"properties":{"preserves-vector-representation":true,"template-rendering-intent":"template"}}' > "$1/$name.imageset/Contents.json"
  done
}
logos "$APP"
# Proxy apps' own App Store icons (Poki/ProxyIcons, see its README) beside their names in Setup.
for png in "$HERE"/Poki/ProxyIcons/*.png; do
  name="Proxy-$(basename "$png" .png)"
  mkdir -p "$APP/$name.imageset"
  cp "$png" "$APP/$name.imageset/icon@3x.png"
  echo '{"images":[{"filename":"icon@3x.png","idiom":"universal","scale":"3x"}],"info":{"version":1,"author":"poki"}}' > "$APP/$name.imageset/Contents.json"
done

# Poki's poses (Poki/BearPoses): the bear in its window, on the New chat pill and in Settings.
for png in "$HERE"/Poki/BearPoses/*.png; do
  name="Pose-$(basename "$png" .png)"
  mkdir -p "$APP/$name.imageset"
  cp "$png" "$APP/$name.imageset/pose@3x.png"
  echo '{"images":[{"filename":"pose@3x.png","idiom":"universal","scale":"3x"}],"info":{"version":1,"author":"poki"}}' > "$APP/$name.imageset/Contents.json"
done

WIDGET="$HERE/PokiWidgets/Assets.xcassets"
catalog "$WIDGET"
bear "$WIDGET"
# The calling agent's logo on the Live Activity.
logos "$WIDGET"
# Poki's poses for the Live Activity, small: the largest it draws is 40 points.
for png in "$HERE"/Poki/BearPoses/*.png; do
  name="Pose-$(basename "$png" .png)"
  mkdir -p "$WIDGET/$name.imageset"
  sips -Z 132 "$png" --out "$WIDGET/$name.imageset/pose@3x.png" >/dev/null
  echo '{"images":[{"filename":"pose@3x.png","idiom":"universal","scale":"3x"}],"info":{"version":1,"author":"poki"}}' > "$WIDGET/$name.imageset/Contents.json"
done
echo "assets in $APP and $WIDGET"
