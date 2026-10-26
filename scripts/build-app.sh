#!/bin/bash
# Chack! 앱 번들을 만들어요.
#   bash scripts/build-app.sh arm64   → dist/arm64/Chack!.app   (애플 실리콘)
#   bash scripts/build-app.sh x86_64  → dist/x86_64/Chack!.app  (인텔)
set -euo pipefail
cd "$(dirname "$0")/.."

ARCH="${1:-$(uname -m)}"
case "$ARCH" in arm64|x86_64) ;; *) echo "arm64 또는 x86_64 중 하나를 넣어주세요"; exit 1;; esac

EXE="Chack"
APP="Chack!.app"
BUNDLE_ID="com.joukey123.chack"
VERSION=$(grep '"version"' version.json | sed -E 's/.*"([0-9][0-9.]*)".*/\1/')
BUILD_NO="${BUILD_NO:-$(date +%Y%m%d%H%M)}"
OUTDIR="dist/$ARCH"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

echo "▶ Chack! v$VERSION ($ARCH) 컴파일"
xcrun swiftc -O -parse-as-library -swift-version 5 \
  -target "$ARCH-apple-macos13.0" \
  -o "$WORK/$EXE" Sources/*.swift

echo "▶ 아이콘"
ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2))
  sips -z $d $d Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$WORK/AppIcon.icns"

echo "▶ 앱 묶기"
rm -rf "$OUTDIR/$APP"
mkdir -p "$OUTDIR/$APP/Contents/MacOS" "$OUTDIR/$APP/Contents/Resources/Fonts"
OUT="$OUTDIR/$APP"
cp "$WORK/$EXE" "$OUT/Contents/MacOS/$EXE"
cp "$WORK/AppIcon.icns" "$OUT/Contents/Resources/AppIcon.icns"
cp Resources/Mark.png "$OUT/Contents/Resources/Mark.png"
cp Resources/Fonts/*.ttf "$OUT/Contents/Resources/Fonts/"
cat > "$OUT/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>$EXE</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>Chack!</string>
  <key>CFBundleDisplayName</key><string>Chack!</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NO</string>
  <key>CFBundleDevelopmentRegion</key><string>ko</string>
  <key>ChackArch</key><string>$ARCH</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.finance</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>Chack! · 월간 가계부</string>
</dict>
</plist>
PLIST
codesign --force --deep --sign - "$OUT"
echo "✅ $OUT"
