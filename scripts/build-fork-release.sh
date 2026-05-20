#!/usr/bin/env bash
set -euo pipefail

# Build, sign, notarize, DMG, and publish a cmux release from a personal fork.
#
# Unlike scripts/build-sign-upload.sh (which targets manaflow-ai/cmux and needs
# Apple's restricted passkey provisioning profile), this script:
#   - signs with your own Developer ID cert and cmux.fork.entitlements
#   - points Sparkle auto-update at YOUR fork's releases
#   - publishes the GitHub release to YOUR fork
#
# Usage:
#   ./scripts/build-fork-release.sh <tag>
#
# Required env (export before running, e.g. from ~/.secrets/cmux-fork.env):
#   APPLE_ID                     Apple ID email for notarization
#   APPLE_TEAM_ID                Developer team ID (e.g. D22PZDCXY5)
#   APPLE_APP_SPECIFIC_PASSWORD  app-specific password for notarytool
#   SPARKLE_PRIVATE_KEY          base64 Sparkle EdDSA private key (see below)
#
# Optional env:
#   CMUX_FORK_REPO          GitHub repo to publish to (default: philip-zhan/cmux2)
#   CMUX_FORK_SIGN_IDENTITY codesign identity
#                           (default: Developer ID Application: Draft Technologies Ltd (D22PZDCXY5))
#
# First-time setup for Sparkle:
#   SPARKLE_ENV_FILE=~/.secrets/cmux-fork.env ./scripts/sparkle_generate_keys.sh
#   then: source ~/.secrets/cmux-fork.env

usage() { echo "Usage: ./scripts/build-fork-release.sh <tag>" >&2; }

if [[ $# -ne 1 ]]; then usage; exit 1; fi
TAG="$1"

REPO="${CMUX_FORK_REPO:-philip-zhan/cmux2}"
SIGN_IDENTITY="${CMUX_FORK_SIGN_IDENTITY:-Developer ID Application: Draft Technologies Ltd (D22PZDCXY5)}"
ENTITLEMENTS="cmux.fork.entitlements"
# The fork build ships as "cmux2" with its own bundle identifier so it can be
# installed and run alongside a stock "cmux" without sharing its control socket.
CMUX2_APP_NAME="cmux2"
CMUX2_BUNDLE_ID="com.cmuxterm.cmux2"
BUILT_APP_PATH="build-fork/Build/Products/Release/cmux.app"
APP_PATH="build-fork/Build/Products/Release/${CMUX2_APP_NAME}.app"
GHOSTTYKIT_CRASH_REPORT_SUBDIR="cmux/crash"

# --- Pre-flight ---
for var in APPLE_ID APPLE_TEAM_ID APPLE_APP_SPECIFIC_PASSWORD SPARKLE_PRIVATE_KEY; do
  if [[ -z "${!var:-}" ]]; then echo "MISSING env: $var" >&2; exit 1; fi
done
for tool in xcodebuild create-dmg xcrun codesign ditto gh swift curl python3; do
  command -v "$tool" >/dev/null || { echo "MISSING tool: $tool" >&2; exit 1; }
done
if [[ ! -f "$ENTITLEMENTS" ]]; then echo "MISSING: $ENTITLEMENTS" >&2; exit 1; fi
echo "Pre-flight checks passed (repo=$REPO, tag=$TAG)"

# --- Fetch GhosttyKit (prebuilt, pinned to the ghostty submodule SHA) ---
# CI downloads a prebuilt xcframework rather than building ghostty from source
# (which needs the Metal toolchain and gettext). Do the same here.
echo "Downloading prebuilt GhosttyKit..."
GHOSTTYKIT_CRASH_REPORT_SUBDIR="$GHOSTTYKIT_CRASH_REPORT_SUBDIR" \
  ./scripts/download-prebuilt-ghosttykit.sh

# --- Build app (universal Release, unsigned) ---
echo "Building app (arm64 + x86_64)..."
rm -rf build-fork/
xcodebuild -scheme cmux -configuration Release -derivedDataPath build-fork \
  -destination 'generic/platform=macOS' \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
echo "Build succeeded"

# --- Rebrand as cmux2 (installs alongside a stock cmux) ---
echo "Rebranding app to ${CMUX2_APP_NAME} (${CMUX2_BUNDLE_ID})..."
rm -rf "$APP_PATH"
mv "$BUILT_APP_PATH" "$APP_PATH"
REBRAND_PLIST="$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName $CMUX2_APP_NAME" "$REBRAND_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $CMUX2_APP_NAME" "$REBRAND_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $CMUX2_BUNDLE_ID" "$REBRAND_PLIST"

# --- Inject Sparkle keys + fork feed URL ---
echo "Injecting Sparkle keys..."
SPARKLE_PUBLIC_KEY_DERIVED=$(swift scripts/derive_sparkle_public_key.swift "$SPARKLE_PRIVATE_KEY")
APP_PLIST="$APP_PATH/Contents/Info.plist"
FEED_URL="https://github.com/$REPO/releases/latest/download/appcast.xml"
/usr/libexec/PlistBuddy -c "Delete :SUPublicEDKey" "$APP_PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Delete :SUFeedURL" "$APP_PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $SPARKLE_PUBLIC_KEY_DERIVED" "$APP_PLIST"
/usr/libexec/PlistBuddy -c "Add :SUFeedURL string $FEED_URL" "$APP_PLIST"
echo "Sparkle feed: $FEED_URL"

# --- Codesign (inside-out; Tahoe-safe) ---
echo "Codesigning with: $SIGN_IDENTITY"
./scripts/sign-cmux-bundle.sh "$APP_PATH" "$ENTITLEMENTS" "$SIGN_IDENTITY"

# --- Notarize app ---
echo "Notarizing app..."
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" cmux-notary.zip
xcrun notarytool submit cmux-notary.zip \
  --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" \
  --password "$APPLE_APP_SPECIFIC_PASSWORD" --wait
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"
rm -f cmux-notary.zip
spctl -a -vv --type execute "$APP_PATH"
echo "App notarized"

# --- Create + notarize DMG ---
echo "Creating DMG..."
rm -f cmux-macos.dmg
create-dmg --identity="$SIGN_IDENTITY" "$APP_PATH" ./
mv ./cmux*.dmg cmux-macos.dmg
echo "Notarizing DMG..."
xcrun notarytool submit cmux-macos.dmg \
  --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" \
  --password "$APPLE_APP_SPECIFIC_PASSWORD" --wait
xcrun stapler staple cmux-macos.dmg
xcrun stapler validate cmux-macos.dmg
echo "DMG notarized"

# --- Generate Sparkle appcast pointing at the fork ---
echo "Generating appcast..."
DOWNLOAD_URL_PREFIX="https://github.com/$REPO/releases/download/$TAG/" \
RELEASE_NOTES_URL="https://github.com/$REPO/releases/tag/$TAG" \
  ./scripts/sparkle_generate_appcast.sh cmux-macos.dmg "$TAG" appcast.xml

# --- Publish GitHub release on the fork ---
if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  echo "Uploading to existing release $TAG..."
  gh release upload "$TAG" cmux-macos.dmg appcast.xml --repo "$REPO" --clobber
else
  echo "Creating release $TAG..."
  gh release create "$TAG" cmux-macos.dmg appcast.xml \
    --repo "$REPO" --title "$TAG" --notes "See CHANGELOG.md for details"
fi
gh release view "$TAG" --repo "$REPO"

# --- Cleanup ---
rm -rf build-fork/ cmux-macos.dmg appcast.xml
echo ""
echo "=== Fork release $TAG complete: https://github.com/$REPO/releases/tag/$TAG ==="
