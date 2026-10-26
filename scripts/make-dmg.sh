#!/bin/bash
# 앱을 DMG로 묶어요. 열면 Chack!.app과 응용 프로그램 폴더 바로가기가 보여요.
#   bash scripts/make-dmg.sh arm64   → dist/Chack-AppleSilicon.dmg
#   bash scripts/make-dmg.sh x86_64  → dist/Chack-Intel.dmg
set -euo pipefail
cd "$(dirname "$0")/.."

ARCH="$1"
case "$ARCH" in
  arm64) NAME="Chack-AppleSilicon" ;;
  x86_64) NAME="Chack-Intel" ;;
  *) echo "arm64 또는 x86_64"; exit 1 ;;
esac
APP="dist/$ARCH/Chack!.app"
[ -d "$APP" ] || { echo "$APP 이 없어요. 먼저 build-app.sh를 실행하세요."; exit 1; }

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/처음 열 때 읽어주세요.txt" <<'TXT'
Chack! 설치 방법

1. Chack! 아이콘을 오른쪽 Applications(응용 프로그램) 폴더로 끌어다 놓아요.
2. 응용 프로그램 폴더에서 Chack!을 열어요.

"Apple에서 확인할 수 없어 열 수 없음" 창이 뜨면
  → 완료(또는 취소)를 누른 뒤
  → 시스템 설정 › 개인정보 보호 및 보안 › 아래쪽의 "그래도 열기"를 눌러요.
  (개발자 인증서 없이 직접 배포하는 앱이라 처음 한 번만 이렇게 열어요.)

또는 터미널에 아래 한 줄을 붙여넣어도 돼요:
  xattr -dr com.apple.quarantine "/Applications/Chack!.app"

이후 업데이트는 앱의 설정 › 업데이트 설치로 할 수 있어요.
가계부 기록은 iCloud Drive › Chack 폴더에 저장되고, 업데이트해도 그대로 남아요.
TXT

mkdir -p dist
rm -f "dist/$NAME.dmg"
hdiutil create -volname "Chack!" -srcfolder "$STAGE" -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "dist/$NAME.dmg" >/dev/null
echo "✅ dist/$NAME.dmg ($(du -h "dist/$NAME.dmg" | cut -f1))"
