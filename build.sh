#!/bin/bash
# 차곡 맥 앱을 이 맥에서 빌드해 /Applications 에 설치해요.
# 가계부 기록(iCloud Drive/차곡)은 건드리지 않아요.
set -euo pipefail
cd "$(dirname "$0")"

EXE="Chagok"
APP="차곡.app"
VERSION=$(grep '"version"' version.json | sed -E 's/.*"([0-9][0-9.]*)".*/\1/')
BUILD_NO=$(date +%Y%m%d%H%M)

echo "🔧 차곡 v$VERSION 빌드를 시작해요"

if ! xcrun --find swiftc >/dev/null 2>&1; then
  echo "명령어 도구(Command Line Tools)가 필요해요. 설치 창을 띄울게요."
  xcode-select --install || true
  echo "설치가 끝나면 이 명령을 한 번 더 실행해주세요."
  exit 1
fi

ARCH=$(uname -m)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

echo "1/4 앱 컴파일 중… (1~3분 걸릴 수 있어요)"
xcrun swiftc -O -parse-as-library -swift-version 5 \
  -target "$ARCH-apple-macos13.0" \
  -o "$WORK/$EXE" Sources/*.swift

echo "2/4 아이콘 만드는 중…"
xcrun swiftc -O -o "$WORK/makeicon" Tools/makeicon.swift
"$WORK/makeicon" "$WORK/icon.png"
ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$WORK/icon.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2))
  sips -z $d $d "$WORK/icon.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$WORK/AppIcon.icns"

echo "3/4 앱 묶는 중…"
OUT="$WORK/$APP"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources/Fonts"
cp "$WORK/$EXE" "$OUT/Contents/MacOS/$EXE"
cp "$WORK/AppIcon.icns" "$OUT/Contents/Resources/AppIcon.icns"
cp Resources/Fonts/*.ttf "$OUT/Contents/Resources/Fonts/"
cat > "$OUT/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>$EXE</string>
  <key>CFBundleIdentifier</key><string>com.joukey123.chagok</string>
  <key>CFBundleName</key><string>차곡</string>
  <key>CFBundleDisplayName</key><string>차곡</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NO</string>
  <key>CFBundleDevelopmentRegion</key><string>ko</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.finance</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>차곡 · 월간 가계부</string>
</dict>
</plist>
PLIST
codesign --force --deep --sign - "$OUT" >/dev/null 2>&1 || true

# GitHub 자동 빌드에서는 설치하지 않고 결과만 남김
if [ "${CHAGOK_CI:-}" = "1" ]; then
  rm -rf dist && mkdir -p dist && cp -R "$OUT" dist/
  echo "✅ 빌드 성공: dist/$APP"
  exit 0
fi

echo "4/4 설치 중…"
DEST="/Applications"
[ -w "$DEST" ] || DEST="$HOME/Applications"
mkdir -p "$DEST"
if pgrep -x "$EXE" >/dev/null; then
  osascript -e 'tell application id "com.joukey123.chagok" to quit' >/dev/null 2>&1 || true
  sleep 1
  pkill -x "$EXE" 2>/dev/null || true
  sleep 1
fi
rm -rf "$DEST/$APP"
cp -R "$OUT" "$DEST/$APP"
xattr -dr com.apple.quarantine "$DEST/$APP" 2>/dev/null || true
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST/$APP" >/dev/null 2>&1 || true

echo ""
echo "✅ 완료! $DEST/$APP"
echo "   Launchpad나 Spotlight(⌘+Space)에서 '차곡'으로 실행할 수 있어요."
open "$DEST/$APP"
