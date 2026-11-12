#!/bin/bash
# Builds "build/Markfetti.app".   Usage: ./build.sh [--install]
#   --install  also copies the app to /Applications
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Markfetti.app"

[[ -f Resources/web/vendor/markdown-it/markdown-it.min.js ]] || ./scripts/fetch-vendor.sh
[[ -f Resources/AppIcon.icns ]] || swift scripts/make-icon.swift .

echo "Compiling…"
swift build -c release --arch arm64 --arch x86_64 2>&1 | grep -vE '^\[[0-9]+/[0-9]+\]' || true
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/Markfetti"
[[ -x "$BIN" ]] || { echo "Build failed"; exit 1; }

echo "Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Markfetti"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cp -R Resources/web "$APP/Contents/Resources/web"
printf 'APPL????' > "$APP/Contents/PkgInfo"

codesign --force --deep --sign - "$APP" >/dev/null 2>&1
# Tell Launch Services about the app so Finder offers it in "Open With"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" || true

if [[ "${1:-}" == "--install" ]]; then
  rm -rf "/Applications/Markfetti.app"
  cp -R "$APP" /Applications/
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "/Applications/Markfetti.app" || true
  echo "Installed to /Applications"
fi
echo "Done: $APP"
