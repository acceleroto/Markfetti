#!/bin/bash
# Builds the Mac App Store package: build/Markfetti-<version>-AppStore.pkg
#
# Needs, in your keychain and on disk:
#   • an "Apple Distribution" (or "3rd Party Mac Developer Application") certificate
#   • a "Mac Installer Distribution" (or "3rd Party Mac Developer Installer") certificate
#   • Mac App Store provisioning profiles for com.acceleroto.markfetti, .preview and .thumbnail,
#     in AppStore/profiles/ or ~/Library/MobileDevice/Provisioning Profiles/ (matched by bundle ID)
# Upload the .pkg with Apple's Transporter app (or `xcrun altool --upload-package`).
set -euo pipefail
cd "$(dirname "$0")/.."

./build.sh --appstore
APP="build/appstore/Markfetti.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
PKG="build/Markfetti-$VERSION-AppStore.pkg"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

IDENTITIES=$(security find-identity -v 2>/dev/null || true)
find_identity() { echo "$IDENTITIES" | grep -m1 -E "\"($1)" | sed 's/.*"\(.*\)"/\1/' || true; }
APP_ID=$(find_identity "Apple Distribution|3rd Party Mac Developer Application")
PKG_ID=$(find_identity "Mac Installer Distribution|3rd Party Mac Developer Installer")
[[ -n "$APP_ID" ]] || { echo "No Apple Distribution certificate found. Create one in Xcode ▸ Settings ▸ Accounts ▸ Manage Certificates."; exit 1; }
[[ -n "$PKG_ID" ]] || { echo "No Mac Installer Distribution certificate found. Create one in Xcode ▸ Settings ▸ Accounts ▸ Manage Certificates."; exit 1; }
echo "Signing with: $APP_ID"
echo "Packaging with: $PKG_ID"

# Finds the Mac App Store (distribution) profile whose application identifier ends in .<bundle id>.
find_profile() {
  local bundle=$1 f plist="$WORK/profile.plist"
  for f in AppStore/profiles/* "$HOME/Library/MobileDevice/Provisioning Profiles/"* \
           "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles/"*; do
    [[ "$f" == *.provisionprofile || "$f" == *.mobileprovision ]] || continue
    [[ -f "$f" ]] || continue
    security cms -D -i "$f" > "$plist" 2>/dev/null || continue
    local appid; appid=$(/usr/libexec/PlistBuddy -c "Print :Entitlements:com.apple.application-identifier" "$plist" 2>/dev/null || true)
    [[ "$appid" == *."$bundle" ]] || continue
    /usr/libexec/PlistBuddy -c "Print :ProvisionedDevices" "$plist" >/dev/null 2>&1 && continue   # development profile
    echo "$f"; return 0
  done
  return 1
}

# Signs one bundle: embeds its profile and adds the identifier entitlements from it.
sign_bundle() {   # sign_bundle <bundle path> <base entitlements>
  local bundle=$1 base=$2
  local id; id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$bundle/Contents/Info.plist")
  local profile; profile=$(find_profile "$id") || {
    echo "No Mac App Store provisioning profile for $id."
    echo "Create one at developer.apple.com ▸ Profiles (Distribution ▸ Mac App Store Connect), download it,"
    echo "and put it in AppStore/profiles/."; exit 1; }
  echo "  $id ← $(basename "$profile")"
  cp "$profile" "$bundle/Contents/embedded.provisionprofile"
  security cms -D -i "$profile" > "$WORK/p.plist"
  local team appid
  team=$(/usr/libexec/PlistBuddy -c "Print :TeamIdentifier:0" "$WORK/p.plist")
  appid=$(/usr/libexec/PlistBuddy -c "Print :Entitlements:com.apple.application-identifier" "$WORK/p.plist")
  cp "$base" "$WORK/ent.plist"
  /usr/libexec/PlistBuddy -c "Add :com.apple.application-identifier string $appid" \
                          -c "Add :com.apple.developer.team-identifier string $team" "$WORK/ent.plist"
  codesign --force --sign "$APP_ID" --entitlements "$WORK/ent.plist" "$bundle"
}

echo "Signing for the App Store…"
for appex in "$APP"/Contents/PlugIns/*.appex; do sign_bundle "$appex" AppStore/Extension.entitlements; done
sign_bundle "$APP" AppStore/Markfetti.entitlements
codesign --verify --deep --strict "$APP"

rm -f "$PKG"
productbuild --component "$APP" /Applications --sign "$PKG_ID" "$PKG"
pkgutil --check-signature "$PKG" | head -3
echo "Done: $PKG — upload it with Transporter."
