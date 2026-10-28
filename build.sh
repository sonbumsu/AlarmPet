#!/bin/bash
# Builds build/NotiPet.app with swiftc (Xcode not required — Command Line Tools are enough).
#   ./build.sh          # build
#   ./build.sh --run    # build and launch
set -euo pipefail
cd "$(dirname "$0")"

OUT="build/NotiPet.app"
SDK=$(xcrun --sdk macosx --show-sdk-path)
ARCH=$(uname -m)

# Assemble and sign outside the project folder: iCloud Drive adds Finder xattrs
# to new files, and codesign refuses to sign bundles that have them.
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/NotiPet.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

find NotiPet -name '*.swift' -print0 | xargs -0 swiftc \
  -sdk "$SDK" -target "$ARCH-apple-macosx14.0" -O \
  -framework AppKit -framework AVFoundation -framework CoreGraphics \
  -framework ServiceManagement -framework Network -framework ApplicationServices \
  -o "$APP/Contents/MacOS/NotiPet"

cp NotiPet/App/Info.plist "$APP/Contents/Info.plist"
iconutil -c icns NotiPet/Resources/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

# Sign with the local "NotiPet Dev" certificate if it exists: its identity stays the same
# across rebuilds, so the Accessibility permission keeps working. Without it we fall back to
# an ad-hoc signature, which changes every build (permission must be re-granted each time).
IDENTITY="${NOTIPET_SIGN_IDENTITY:-NotiPet Dev}"
# Made before the rename to NotiPet: still a stable identity, so keep using it.
if ! security find-certificate -c "$IDENTITY" >/dev/null 2>&1 && security find-certificate -c "AlarmPet Dev" >/dev/null 2>&1; then
  IDENTITY="AlarmPet Dev"
fi
if security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
  codesign --force --sign "$IDENTITY" --identifier com.sonbumsu.notipet "$APP"
else
  echo "⚠️  '$IDENTITY' 인증서가 없어 ad-hoc 서명합니다 (빌드마다 손쉬운 사용 권한을 다시 줘야 해요)"
  echo "    한 번만 ./scripts/setup-signing.sh 를 실행하면 해결돼요."
  codesign --force --sign - --identifier com.sonbumsu.notipet "$APP"
fi

mkdir -p build
rm -rf "$OUT"
ditto "$APP" "$OUT"
echo "✅ $OUT"

if [[ "${1:-}" == "--run" ]]; then
  pkill -x NotiPet 2>/dev/null || true
  pkill -x AlarmPet 2>/dev/null || true   # the app's old name
  open "$OUT"
fi
