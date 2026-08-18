#!/bin/bash
#
# Guarantee 6 (DESIGN 4.2): clipboard payloads, previews, and item text must never reach a log
# message. Counts, byte sizes, type counts, and enum names are fine and are what the app logs.
#
# Run from the repository root. Exits non-zero if a log line looks like it interpolates content.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

echo "Auditing log statements for payload leaks..."

# Payload-bearing expressions. .count and .rawValue are explicitly allowed, which is why the
# patterns below require something other than a count to follow.
SUSPECT='Log\.[a-z]+\.[a-z]+\(.*\\\((item\.preview|item\.plainText|representation\.data|\.data\)|preview\)|thumbnailPNG|plaintext|String\(data:)'

MATCHES=$(grep -rnE "$SUSPECT" ClipPanel --include="*.swift" || true)

if [ -n "$MATCHES" ]; then
  echo "FAIL: log statements appear to reference clipboard content:"
  echo "$MATCHES"
  exit 1
fi

TOTAL=$(grep -rcE "Log\.[a-z]+\.[a-z]+\(" ClipPanel --include="*.swift" | awk -F: '{sum += $2} END {print sum}')
echo "PASS: $TOTAL log statements, none referencing payloads, previews, or item text"
