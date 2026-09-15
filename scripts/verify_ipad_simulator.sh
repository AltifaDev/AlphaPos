#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
XCODE_DIR="${DEVELOPER_DIR:-/Users/mac/Applications/Xcode-beta.app/Contents/Developer}"
if [[ ! -x "$XCODE_DIR/usr/bin/xcodebuild" ]]; then
  echo "iPad Simulator verification skipped: Xcode not found at $XCODE_DIR"
  exit 1
fi

DEVICE_ID="$(DEVELOPER_DIR="$XCODE_DIR" /usr/bin/xcrun simctl list devices available -j | jq -r '[.devices[][] | select((.name | startswith("iPad")) and .state == "Booted")][0].udid // [.devices[][] | select(.name | startswith("iPad"))][0].udid // empty')"
if [[ -z "$DEVICE_ID" ]]; then
  echo "iPad Simulator verification failed: no available iPad simulator."
  exit 1
fi

DERIVED_DIR="$ROOT_DIR/.build/ipad-simulator-derived"
BUILD_LOG="$ROOT_DIR/.build/ipad-simulator-build.log"
mkdir -p "$DERIVED_DIR"

if ! DEVELOPER_DIR="$XCODE_DIR" "$XCODE_DIR/usr/bin/xcodebuild" \
  -project "$ROOT_DIR/AlphaPos.xcodeproj" -scheme AlphaPos \
  -destination "platform=iOS Simulator,id=$DEVICE_ID" \
  -derivedDataPath "$DERIVED_DIR" -jobs 2 \
  SWIFT_COMPILATION_MODE=incremental build >"$BUILD_LOG" 2>&1; then
  tail -n 120 "$BUILD_LOG"
  exit 1
fi

APP_PATH="$DERIVED_DIR/Build/Products/Debug-iphonesimulator/AlphaPos.app"
DEVELOPER_DIR="$XCODE_DIR" /usr/bin/xcrun simctl bootstatus "$DEVICE_ID" -b >/dev/null
DEVELOPER_DIR="$XCODE_DIR" /usr/bin/xcrun simctl install "$DEVICE_ID" "$APP_PATH"
LAUNCH_OUTPUT="$(DEVELOPER_DIR="$XCODE_DIR" /usr/bin/xcrun simctl launch "$DEVICE_ID" AltifaDev.AlphaPos)"
if [[ ! "$LAUNCH_OUTPUT" =~ AltifaDev.AlphaPos:[[:space:]][0-9]+ ]]; then
  echo "iPad Simulator verification failed: app did not return a process id."
  exit 1
fi
echo "iPad Simulator build/install/launch passed on $DEVICE_ID"
