#!/bin/bash
#
# Static verification of the DESIGN 4.2 guarantees against a built Release app, plus the build
# configuration decisions from DESIGN 6.4. Run after building Release.
#
#   Scripts/verify-release.sh /path/to/ClipPanel.app
#
# Exits non-zero on any failure, so it can gate a release.

set -uo pipefail

APP="${1:-}"
if [ -z "$APP" ] || [ ! -d "$APP" ]; then
  echo "usage: $0 /path/to/ClipPanel.app"
  exit 2
fi
BIN="$APP/Contents/MacOS/ClipPanel"
FAILURES=0

check() {
  if [ "$2" = "pass" ]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1${3:+  ($3)}"
    FAILURES=$((FAILURES + 1))
  fi
}

# Framework allowlist: every directly-linked framework must be one this app has a stated reason to
# use. A new framework appearing here should be a conscious decision, not a surprise in an audit.
# Reasons: Foundation/AppKit/SwiftUI/CoreFoundation/CoreGraphics are the app;
# Carbon is RegisterEventHotKey; ApplicationServices is AXIsProcessTrusted;
# LocalAuthentication is the Touch ID gate; ServiceManagement is the login item;
# Security/CryptoKit are the pin encryption and its keychain key.
ALLOWED_FRAMEWORKS="Foundation|AppKit|Carbon|CoreGraphics|CoreFoundation|SwiftUI|ApplicationServices|LocalAuthentication|ServiceManagement|Security|CryptoKit"
UNEXPECTED=$(otool -L "$BIN" | tail -n +2 | grep -oE '/([A-Za-z]+)\.framework' | sed 's|/||;s|\.framework||' | sort -u | grep -vE "^($ALLOWED_FRAMEWORKS)$" || true)
if [ -n "$UNEXPECTED" ]; then
  check "only expected frameworks linked" fail "$(echo "$UNEXPECTED" | tr '\n' ' ')"
else
  check "only expected frameworks linked" pass
fi

# Guarantee 1: no networking. Foundation is always linked and contains URLSession, so the meaningful
# checks are that no networking framework is linked and no networking symbol is imported.
if otool -L "$BIN" | grep -qiE "Network\.framework|CFNetwork"; then
  check "no networking framework linked" fail "$(otool -L "$BIN" | grep -iE 'Network\.framework|CFNetwork' | head -1)"
else
  check "no networking framework linked" pass
fi

NET_SYMS=$(nm -u "$BIN" 2>/dev/null | grep -cE "URLSession|NSURLConnection|NWConnection|getaddrinfo|CFStreamCreatePairWithSocket" || true)
check "no networking symbols imported" "$([ "$NET_SYMS" -eq 0 ] && echo pass || echo fail)" "$NET_SYMS found"

# Debug affordances must not exist in a shipping build.
SELFTEST_SYMS=$(nm -a "$BIN" 2>/dev/null | grep -ci selftest || true)
SELFTEST_STRS=$(strings "$BIN" | grep -c CLIPPANEL_SELFTEST || true)
check "self test compiled out" "$([ "$SELFTEST_SYMS" -eq 0 ] && echo pass || echo fail)" "$SELFTEST_SYMS symbols"
check "self test environment variable absent" "$([ "$SELFTEST_STRS" -eq 0 ] && echo pass || echo fail)" "$SELFTEST_STRS strings"

# DESIGN 6.4: hardened runtime on, sandbox deliberately off.
if codesign -dv "$APP" 2>&1 | grep -q "runtime"; then
  check "hardened runtime enabled" pass
else
  check "hardened runtime enabled" fail
fi

if codesign -d --entitlements - "$APP" 2>/dev/null | tr -d '\0' | grep -q "app-sandbox"; then
  check "app sandbox absent (blocks synthetic paste, DESIGN 6.4)" fail "sandbox entitlement present"
else
  check "app sandbox absent (blocks synthetic paste, DESIGN 6.4)" pass
fi

# Menu bar agent, no Dock icon.
LSUI=$(/usr/libexec/PlistBuddy -c "Print :LSUIElement" "$APP/Contents/Info.plist" 2>/dev/null || echo "missing")
check "LSUIElement set (menu bar agent)" "$([ "$LSUI" = "true" ] && echo pass || echo fail)" "$LSUI"

# Icon present.
[ -f "$APP/Contents/Resources/AppIcon.icns" ] \
  && check "app icon present" pass \
  || check "app icon present" fail

echo
if [ "$FAILURES" -eq 0 ]; then
  echo "All release checks passed."
else
  echo "$FAILURES check(s) failed."
fi
exit "$FAILURES"
