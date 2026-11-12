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

# Add the platform keys Xcode writes into every bundle's Info.plist. ExtensionKit uses them to
# decide which platforms an extension supports; without them the thumbnail extension is ignored.
SDK_VERSION=$(xcrun --show-sdk-version)
SDK_BUILD=$(xcrun --show-sdk-build-version)
add_platform_keys() {
  local plist=$1
  /usr/libexec/PlistBuddy -c "Delete :CFBundleSupportedPlatforms" "$plist" 2>/dev/null || true
  /usr/libexec/PlistBuddy \
    -c "Add :CFBundleSupportedPlatforms array" -c "Add :CFBundleSupportedPlatforms:0 string MacOSX" \
    -c "Add :DTPlatformName string macosx" -c "Add :DTPlatformVersion string $SDK_VERSION" \
    -c "Add :DTSDKName string macosx$SDK_VERSION" -c "Add :DTSDKBuild string $SDK_BUILD" "$plist" 2>/dev/null || true
}
add_platform_keys "$APP/Contents/Info.plist"

# Code signing identity. Quick Look ignores ad-hoc signed extensions, so prefer a real certificate:
# $SIGN_IDENTITY if set, else "Developer ID Application", else "Apple Development", else ad-hoc.
if [[ -z "${SIGN_IDENTITY:-}" ]]; then
  IDENTITIES=$(security find-identity -v -p codesigning 2>/dev/null || true)
  SIGN_IDENTITY=$(echo "$IDENTITIES" | grep -m1 '"Developer ID Application' | awk '{print $2}' || true)
  [[ -n "$SIGN_IDENTITY" ]] || SIGN_IDENTITY=$(echo "$IDENTITIES" | grep -m1 '"Apple Development' | awk '{print $2}' || true)
  [[ -n "$SIGN_IDENTITY" ]] || SIGN_IDENTITY=-
fi
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  echo "Signing ad-hoc (no certificate found): Quick Look extensions won't load"
else
  echo "Signing with $(security find-identity -v -p codesigning | grep -m1 "$SIGN_IDENTITY" | sed 's/.*"\(.*\)"/\1/')"
fi

# Quick Look extensions (preview + Finder thumbnails). SwiftPM can't build .appex bundles,
# so compile them directly; they read the renderer files from the app's Resources/web.
SDK="$(xcrun --show-sdk-path)"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
BUILDNUM=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" Resources/Info.plist)
SHARED=(Sources/Markfetti/SchemeHandler.swift Sources/Markfetti/RenderPayload.swift Extensions/Shared/ExtensionWebView.swift)
build_extension() {   # build_extension <Name> <frameworks…>
  local name=$1; shift
  local appex="$APP/Contents/PlugIns/Markfetti$name.appex" obj="build/obj/$name"
  echo "Compiling $name extension…"
  mkdir -p "$appex/Contents/MacOS" "$obj"
  local fw=(); for f in "$@"; do fw+=(-framework "$f"); done
  for arch in arm64 x86_64; do
    swiftc -O -swift-version 5 -parse-as-library -application-extension -module-name "Markfetti$name" \
      -target "$arch-apple-macos13.0" -sdk "$SDK" \
      "${SHARED[@]}" Extensions/"$name"/*.swift "${fw[@]}" \
      -Xlinker -application_extension -Xlinker -e -Xlinker _NSExtensionMain \
      -o "$obj/Markfetti$name-$arch"
  done
  lipo -create "$obj/Markfetti$name-arm64" "$obj/Markfetti$name-x86_64" -output "$appex/Contents/MacOS/Markfetti$name"
  cp "Extensions/$name/Info.plist" "$appex/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" -c "Set :CFBundleVersion $BUILDNUM" "$appex/Contents/Info.plist"
  add_platform_keys "$appex/Contents/Info.plist"
  codesign --force --sign "$SIGN_IDENTITY" --timestamp=none --entitlements Extensions/Shared/Extension.entitlements "$appex"
}
build_extension Preview AppKit WebKit Quartz
build_extension Thumbnail AppKit WebKit QuickLookThumbnailing

# Sign the app last (no --deep: that would re-sign the extensions without their entitlements).
codesign --force --sign "$SIGN_IDENTITY" --timestamp=none "$APP"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

if [[ "${1:-}" == "--install" ]]; then
  rm -rf "/Applications/Markfetti.app"
  cp -R "$APP" /Applications/
  # Only the installed copy should provide the Quick Look extensions.
  "$LSREGISTER" -u "$PWD/$APP" >/dev/null 2>&1 || true
  "$LSREGISTER" -f "/Applications/Markfetti.app" || true
  pluginkit -a "/Applications/Markfetti.app/Contents/PlugIns/MarkfettiPreview.appex" 2>/dev/null || true
  pluginkit -a "/Applications/Markfetti.app/Contents/PlugIns/MarkfettiThumbnail.appex" 2>/dev/null || true
  qlmanage -r >/dev/null 2>&1 || true
  qlmanage -r cache >/dev/null 2>&1 || true
  echo "Installed to /Applications"
fi
echo "Done: $APP"
