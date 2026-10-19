#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# The Command Line Tools' macOS 27 SDK ships SwiftUI's property-wrapper macros
# as external plugins that are not present in a CLT-only installation. The
# macOS 26.5 SDK still provides the classic property wrappers, so use it when
# Xcode is not available. The resulting app targets macOS 14+.
if [ -z "${SDKROOT:-}" ]; then
  if [ -d "/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk" ]; then
    SDKROOT="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
  else
    SDKROOT="$(xcrun --show-sdk-path)"
  fi
fi
export SDKROOT

export CLANG_MODULE_CACHE_PATH="$ROOT/.cache/clang"
export SWIFT_MODULECACHE_PATH="$ROOT/.cache/swiftmodules"

swift build -c release --product FocusCull --disable-sandbox \
  --arch arm64 --arch x86_64 \
  --scratch-path .build-app \
  --cache-path .cache/swiftpm \
  --config-path .cache/swiftpm-config \
  --security-path .cache/swiftpm-security

BIN=".build-app/out/Products/Release/FocusCull"

# Assemble outside the (possibly cloud-synced) workspace. File providers add
# FinderInfo xattrs that invalidate an otherwise valid code signature.
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/FocusCull-stage.XXXXXX")"
VERIFY=""
cleanup() {
  rm -rf "$STAGE"
  if [ -n "$VERIFY" ]; then rm -rf "$VERIFY"; fi
}
trap cleanup EXIT
APP_STAGE="$STAGE/FocusCull.app"

mkdir -p "$APP_STAGE/Contents/MacOS" "$APP_STAGE/Contents/Resources"
cp "$BIN" "$APP_STAGE/Contents/MacOS/FocusCull"
cp "$ROOT/Info.plist" "$APP_STAGE/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP_STAGE/Contents/Resources/AppIcon.icns"
chmod +x "$APP_STAGE/Contents/MacOS/FocusCull"

xattr -cr "$APP_STAGE" 2>/dev/null || true
find "$APP_STAGE" -name '.DS_Store' -delete 2>/dev/null || true

/usr/bin/codesign --force --deep --sign - --timestamp=none "$APP_STAGE"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_STAGE"

mkdir -p dist
rm -f "dist/FocusCull-1.5.0-macOS.zip"
COPYFILE_DISABLE=1 /usr/bin/ditto -c -k --norsrc --noextattr --keepParent \
  "$APP_STAGE" "dist/FocusCull-1.5.0-macOS.zip"

# Verify the archive independently, since that is the shipped artifact.
VERIFY="$(mktemp -d "${TMPDIR:-/tmp}/FocusCull-verify.XXXXXX")"
/usr/bin/ditto -x -k "dist/FocusCull-1.5.0-macOS.zip" "$VERIFY"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$VERIFY/FocusCull.app"
lipo -info "$VERIFY/FocusCull.app/Contents/MacOS/FocusCull"

# Keep a convenience copy in the workspace. The zip above is the authoritative
# clean artifact; cloud sync may attach xattrs to this copy after it is written.
rm -rf "dist/release/FocusCull.app"
mkdir -p dist/release
/usr/bin/ditto --norsrc --noextattr "$APP_STAGE" "dist/release/FocusCull.app"

echo "Built: $ROOT/dist/release/FocusCull.app"
echo "Zip:   $ROOT/dist/FocusCull-1.5.0-macOS.zip"
