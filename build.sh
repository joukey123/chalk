#!/bin/bash
# 개발용: 이 맥에서 바로 빌드해 /Applications 에 설치해요.
# 일반 설치는 chack-release 저장소의 DMG를 쓰세요.
set -euo pipefail
cd "$(dirname "$0")"

if ! xcrun --find swiftc >/dev/null 2>&1; then
  echo "명령어 도구(Command Line Tools)가 필요해요. 설치 창을 띄울게요."
  xcode-select --install || true
  echo "설치가 끝나면 이 명령을 한 번 더 실행해주세요."
  exit 1
fi

ARCH=$(uname -m)
bash scripts/build-app.sh "$ARCH"

DEST="/Applications"
[ -w "$DEST" ] || DEST="$HOME/Applications"
mkdir -p "$DEST"
osascript -e 'tell application id "com.joukey123.chack" to quit' >/dev/null 2>&1 || true
sleep 1
rm -rf "$DEST/Chack!.app"
cp -R "dist/$ARCH/Chack!.app" "$DEST/"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST/Chack!.app" >/dev/null 2>&1 || true
echo "✅ $DEST/Chack!.app"
open "$DEST/Chack!.app"
