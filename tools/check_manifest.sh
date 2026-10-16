#!/usr/bin/env bash
# Fails if a RELEASE apk declares network/audio permissions it should not, or
# if OS backup is enabled. Usage: tools/check_manifest.sh path/to/app-release.apk [allow-permission ...]
set -euo pipefail
APK="$1"; shift
ALLOWED=("$@")
PERMS=$(aapt dump permissions "$APK" | sed -n "s/^uses-permission: name='\(.*\)'/\1/p")
echo "Declared permissions:"; echo "$PERMS" | sed 's/^/  /'
fail=0
for p in $PERMS; do
  case "$p" in *.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION) continue;; esac
  ok=0; for a in "${ALLOWED[@]:-}"; do [ "$p" = "$a" ] && ok=1; done
  if [ $ok -eq 0 ]; then echo "UNEXPECTED permission: $p"; fail=1; fi
done
BK=$(aapt dump xmltree "$APK" AndroidManifest.xml | grep -E 'allowBackup' || true)
echo "allowBackup attribute: ${BK:-<absent: defaults to TRUE>}"
echo "$BK" | grep -q '=(type 0x12)0x0' || { echo "allowBackup is not false"; fail=1; }
exit $fail
