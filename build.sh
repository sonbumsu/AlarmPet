#!/bin/bash
# Builds build/AlarmPet.app with swiftc (Xcode not required — Command Line Tools are enough).
#   ./build.sh          # build
#   ./build.sh --run    # build and launch
set -euo pipefail
cd "$(dirname "$0")"

OUT="build/AlarmPet.app"
SDK=$(xcrun --sdk macosx --show-sdk-path)
ARCH=$(uname -m)

# Assemble and sign outside the project folder: iCloud Drive adds Finder xattrs
# to new files, and codesign refuses to sign bundles that have them.
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/AlarmPet.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

find AlarmPet -name '*.swift' -print0 | xargs -0 swiftc \
  -sdk "$SDK" -target "$ARCH-apple-macosx14.0" -O \
  -framework AppKit -framework AVFoundation -framework CoreGraphics \
  -framework ServiceManagement -framework Network -framework ApplicationServices \
  -o "$APP/Contents/MacOS/AlarmPet"

cp AlarmPet/App/Info.plist "$APP/Contents/Info.plist"
iconutil -c icns AlarmPet/Resources/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

# Sign with the local "AlarmPet Dev" certificate if it exists: its identity stays the same
# across rebuilds, so the Accessibility permission keeps working. Without it we fall back to
# an ad-hoc signature, which changes every build (permission must be re-granted each time).
IDENTITY="${ALARMPET_SIGN_IDENTITY:-AlarmPet Dev}"
if security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
  codesign --force --sign "$IDENTITY" --identifier com.sonbumsu.alarmpet "$APP"
else
  echo "⚠️  '$IDENTITY' 인증서가 없어 ad-hoc 서명합니다 (빌드마다 손쉬운 사용 권한을 다시 줘야 해요)"
  echo "    한 번만 ./scripts/setup-signing.sh 를 실행하면 해결돼요."
  codesign --force --sign - --identifier com.sonbumsu.alarmpet "$APP"
fi

mkdir -p build
rm -rf "$OUT"
ditto "$APP" "$OUT"
echo "✅ $OUT"

if [[ "${1:-}" == "--run" ]]; then
  pkill -x AlarmPet 2>/dev/null || true
  open "$OUT"
fi
