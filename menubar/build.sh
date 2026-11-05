#!/bin/sh
# 重建 Poki.app：把 poki 仓库打包成 macOS 菜单栏应用
# 用法：sh build.sh /path/to/poki-checkout
set -eu
SRC=${1:-/path/to/poki-checkout}
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
OUT=${OUT:-/tmp/poki-build}
APP="$OUT/Poki.app"
NODE_VER=v26.13.0

[ -x "$SRC/build/poki-native" ] || { echo "先在该仓库跑 ./bin/setup 完成原生构建" >&2; exit 1; }

rm -rf "$OUT"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/poki/build" "$APP/Contents/Resources/poki/tools"
R="$APP/Contents/Resources/poki"

# 运行时（避开 ~/Documents 的 iCloud 占位符问题：依赖用 npm ci 重建）
rsync -a "$SRC/src" "$SRC/bin" "$SRC/native" "$R/"
cp "$SRC/package.json" "$SRC/package-lock.json" "$R/"
( cd "$R" && npm ci --omit=dev --no-audit --no-fund >/dev/null )
cp "$SRC/build/ocr" "$SRC/build/simulator" "$SRC/build/poki-native" "$R/build/"
cp "$SRC/.deps/idevice/target/release/idevice-tools" "$SRC/.deps/idevice/target/release/idevice_id" "$R/tools/"

# Poki Agent（终端智能体，poki 命令）
rsync -a --exclude test "$SRC/agent" "$R/"
( cd "$R/agent" && npm ci --no-audit --no-fund >/dev/null )

# 官方静态 node（Homebrew 的是 shared 构建，拷走会缺 dylib）
if [ ! -x /tmp/node-dist/node-$NODE_VER-darwin-arm64/bin/node ]; then
  mkdir -p /tmp/node-dist
  curl -sSL -o /tmp/node-dist/node.tar.gz "https://nodejs.org/dist/$NODE_VER/node-$NODE_VER-darwin-arm64.tar.gz"
  tar -xzf /tmp/node-dist/node.tar.gz -C /tmp/node-dist
fi
cp "/tmp/node-dist/node-$NODE_VER-darwin-arm64/bin/node" "$R/node"
chmod 755 "$R/node" "$R/build/"* "$R/tools/"*

# 图标
SRCICON="$SRC/docs/images/poki-icon.png"
I=/tmp/icon.iconset; rm -rf "$I"; mkdir -p "$I"
for s in 16 32 128 256 512; do
  sips -z $s $s "$SRCICON" --out "$I/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$SRCICON" --out "$I/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$I" -o "$APP/Contents/Resources/AppIcon.icns"
sips -z 18 18 "$SRCICON" --out "$APP/Contents/Resources/menubar.png" >/dev/null
sips -z 36 36 "$SRCICON" --out "$APP/Contents/Resources/menubar@2x.png" >/dev/null

cp "$HERE/Info.plist" "$APP/Contents/Info.plist"

# 外壳
xcrun swiftc -O -swift-version 5 -target arm64-apple-macos15.0 -framework Cocoa \
  -o "$APP/Contents/MacOS/Poki" "$HERE/main.swift" "$HERE/SettingsWindow.swift" "$HERE/SettingsWindow.swift"

# 签名（adhoc）
xattr -cr "$APP"
find "$APP" -name "._*" -delete 2>/dev/null || true
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --verbose=2 "$APP"

# DMG
DMG=${DMG:-/tmp/Poki-0.1.0-arm64.dmg}
rm -rf /tmp/poki-dmg; mkdir -p /tmp/poki-dmg
cp -Rc "$APP" /tmp/poki-dmg/
ln -s /Applications /tmp/poki-dmg/Applications
rm -f "$DMG"
hdiutil create -volname "Poki" -srcfolder /tmp/poki-dmg -ov -format UDZO -imagekey zlib-level=9 "$DMG" >/dev/null
echo "完成：$APP"
echo "DMG：$DMG"
echo
echo "装上后加一条命令即可在终端用 poki："
echo '  cat > /opt/homebrew/bin/poki <<EOF'
echo '  #!/bin/sh'
echo "  exec \"$R/node\" \"$R/agent/poki.mjs\" \"\$@\""
echo '  EOF'
echo '  chmod 755 /opt/homebrew/bin/poki'
