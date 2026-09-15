#!/bin/sh
# Fail Release/Archive builds when Cloudflare Turnstile site key is missing.
# Simulator/Debug may omit the key; production TestFlight/App Store must ship it.

set -eu

CONFIG_PLIST="${SRCROOT:-}/AlphaPos/Supporting Files/Config.plist"
CONFIGURATION="${CONFIGURATION:-}"

# Only enforce for Release (Archive / TestFlight / App Store).
case "$CONFIGURATION" in
  Release) ;;
  *)
    echo "note: Skipping Turnstile config check for configuration '${CONFIGURATION}'"
    exit 0
    ;;
esac

if [ ! -f "$CONFIG_PLIST" ]; then
  echo "error: Missing Config.plist at: $CONFIG_PLIST" >&2
  echo "error: Release builds require TURNSTILE_SITE_KEY so the login captcha appears on TestFlight/App Store." >&2
  exit 1
fi

SITE_KEY="$(/usr/libexec/PlistBuddy -c 'Print :TURNSTILE_SITE_KEY' "$CONFIG_PLIST" 2>/dev/null || true)"
SITE_KEY="$(printf '%s' "$SITE_KEY" | tr -d '[:space:]')"

if [ -z "$SITE_KEY" ] || printf '%s' "$SITE_KEY" | grep -qi 'your-'; then
  echo "error: TURNSTILE_SITE_KEY is missing or still a placeholder in Config.plist" >&2
  echo "error: Without this key, MerchantAuthView hides the Cloudflare Turnstile checkbox on device/TestFlight." >&2
  echo "error: Set TURNSTILE_SITE_KEY in: AlphaPos/Supporting Files/Config.plist" >&2
  exit 1
fi

echo "note: Turnstile site key present for Release build (${#SITE_KEY} chars)"
