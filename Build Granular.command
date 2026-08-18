#!/bin/zsh

set -u

ROOT="${0:A:h}"
APP="$ROOT/dist/Granular.app"

pause_before_exit() {
    if [[ -t 0 ]]; then
        echo
        read -k 1 "?Press any key to close this window…"
        echo
    fi
}

fail() {
    echo
    echo "Granular could not be built."
    echo "$1"
    pause_before_exit
    exit 1
}

cd "$ROOT" || fail "The Granular source folder could not be opened."

MACOS_MAJOR="$(/usr/bin/sw_vers -productVersion | /usr/bin/cut -d. -f1)"
if (( MACOS_MAJOR < 26 )); then
    fail "Granular requires macOS 26 or later."
fi

DEVELOPER_DIR="$(/usr/bin/xcode-select -p 2>/dev/null)" \
    || fail "Install the full Xcode 26 application, open it once, and try again."

if ! /usr/bin/xcodebuild -version >/dev/null 2>&1; then
    fail "Xcode is not ready. Open Xcode once and allow it to install its required components."
fi

ICON_TOOL="$DEVELOPER_DIR/../Applications/Icon Composer.app/Contents/Executables/ictool"
if [[ ! -x "$ICON_TOOL" ]]; then
    fail "Granular needs the full Xcode 26 application, including Icon Composer. Command Line Tools alone are not enough."
fi

echo "Building Granular…"
echo

if ! "$ROOT/Scripts/build-app.sh"; then
    fail "See the build output above for details."
fi

if [[ ! -d "$APP" ]]; then
    fail "The build finished without creating dist/Granular.app."
fi

echo
echo "Granular is ready:"
echo "$APP"
echo
echo "Drag Granular.app into Applications if you want to install it."

if [[ "${GRANULAR_SKIP_REVEAL:-0}" != "1" ]]; then
    /usr/bin/open -R "$APP"
    pause_before_exit
fi
