#!/usr/bin/env bash
#
# list-drives.sh - show model, OEM id, firmware revision and link speed of
#                  all /dev/sd? drives, to decide which ones this guide covers.
#
# Read-only: uses "smartctl -i" only. Run as root.

set -u

command -v smartctl >/dev/null 2>&1 || { echo "smartctl not found - install smartmontools" >&2; exit 1; }

printf '%-10s %-24s %-10s %-9s %s\n' "DEVICE" "MODEL" "OEM" "FIRMWARE" "SATA"
for dev in /dev/sd?; do
  [ -b "$dev" ] || continue
  info=$(smartctl -i "$dev" 2>/dev/null) || true
  model=$(printf '%s\n' "$info" | sed -n 's/^Device Model: *//p')
  oem=$(printf '%s\n' "$info"   | sed -n 's/^Add\. Product Id: *//p')
  fw=$(printf '%s\n' "$info"    | sed -n 's/^Firmware Version: *//p')
  sata=$(printf '%s\n' "$info"  | sed -n 's/^SATA Version is: *//p')
  printf '%-10s %-24s %-10s %-9s %s\n' "$dev" "${model:--}" "${oem:--}" "${fw:--}" "${sata:--}"
done

cat <<'EOF'

This guide applies to a drive only if:
  MODEL    is ST4000NM0033-9ZM170, ST3000NM0033-9ZM178, ST2000NM0033-9ZM175,
           ST1000NM0033-9ZM173 or ST500NM0003-9ZM172
  OEM      is DELL(tm)
  FIRMWARE starts with GA0 (GA06, GA0A, GA0D, GA0F ...) and is not GA10 yet
EOF
