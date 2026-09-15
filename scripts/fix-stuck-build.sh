#!/usr/bin/env bash
# Unstick Xcode AlphaPos build stuck mid-Archive (Swift Release compile).
# Translations live in Resources/translations.json (not a Swift dictionary literal).
set -euo pipefail

echo "==> Stopping stuck compilers (Xcode stays open; stop the build first if you can)"
pkill -f 'swift-frontend.*AlphaPos' 2>/dev/null || true
pkill -f 'xcodebuild.*AlphaPos' 2>/dev/null || true
sleep 1

echo "==> Removing AlphaPos DerivedData (forces clean rebuild)"
rm -rf "${HOME}/Library/Developer/Xcode/DerivedData/AlphaPos-"*
rm -rf "${HOME}/Library/Developer/Xcode/DerivedData/AlphaPosStaff-"* 2>/dev/null || true

echo "==> Done."
echo
echo "Next:"
echo "  CLI: xcodebuild -project AlphaPos.xcodeproj -scheme AlphaPos -configuration Release \\"
echo "         -destination 'generic/platform=iOS' -archivePath AppStoreBuild/AlphaPos.xcarchive archive"
echo "  Or Xcode: destination Any iOS Device → Product → Archive"
echo
echo "If Activity Monitor shows swift-frontend at high CPU, it is still working — wait."
echo "If CPU is ~0% for >5 minutes, run this script again."
