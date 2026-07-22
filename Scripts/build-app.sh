#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP="$ROOT/dist/Filmify.app"
CONTENTS="$APP/Contents"

cd "$ROOT"
swift build -c release

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$ROOT/.build/release/Filmify" "$CONTENTS/MacOS/Filmify"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
xcrun actool \
    "$ROOT/Resources/Assets.xcassets" \
    --compile "$CONTENTS/Resources" \
    --platform macosx \
    --minimum-deployment-target 26.0 \
    --app-icon AppIcon \
    --output-partial-info-plist "$ROOT/.build/Filmify-asset-info.plist"

codesign \
    --force \
    --deep \
    --sign - \
    --entitlements "$ROOT/Resources/Filmify.entitlements" \
    "$APP"

codesign --verify --deep --strict "$APP"
echo "$APP"
