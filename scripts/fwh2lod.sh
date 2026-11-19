#!/usr/bin/env bash
#
# fwh2lod.sh - convert a Dell ".fwh" hard-drive firmware file into a plain
#              Seagate ".lod" image by removing the Dell wrapper header,
#              and verify the result.
#
# The script only reads the input file and writes a new file.
# It never touches a disk and never flashes anything.
#
# Usage:
#   fwh2lod.sh [-f] [-m MODEL] INPUT.fwh [OUTPUT.lod]
#
#   -f        overwrite OUTPUT if it already exists
#   -m MODEL  additionally require that MODEL (e.g. ST1000NM0033-9ZM173)
#             is listed in the Dell header
#
# Exit status: 0 = image written and all checks passed, 1 = a check failed.
#
# Header layout this script relies on (see docs/fwh-header-format.md):
#   0x00  8 bytes   "    DELL"
#   0x09  4 bytes   firmware revision contained in the file (e.g. "GA10")
#   0x3F  1 byte    number N of model entries
#   0x40  N * 48    model entries (8 char number + 40 char model, space padded)
#   0x40 + N*48     start of the Seagate LOD image
#
# Checks performed on the LOD image:
#   1. its length is a multiple of 512 bytes (required by hdparm)
#   2. the 16-bit words of its first 64 bytes sum up to 0 (header checksum)
#   3. the 32-bit length field at offset 0x24 equals the real length

set -euo pipefail

# SHA-256 of the GA10.lod image that was flashed successfully (see README).
known_ga10_sha256="6a261b8bab566d7f014d2dd49f72f65b089d3b322348c69029545a7d18422625"

die()  { echo "ERROR: $*" >&2; exit 1; }
note() { echo "$*"; }

force=0
want_model=""
while getopts ":fm:h" opt; do
  case "$opt" in
    f) force=1 ;;
    m) want_model="$OPTARG" ;;
    h) awk 'NR>1 && /^#/ {sub(/^# ?/,""); print; next} NR>1 {exit}' "$0"; exit 0 ;;
    *) die "unknown option. Usage: $0 [-f] [-m MODEL] INPUT.fwh [OUTPUT.lod]" ;;
  esac
done
shift $((OPTIND - 1))

[ $# -ge 1 ] && [ $# -le 2 ] || die "Usage: $0 [-f] [-m MODEL] INPUT.fwh [OUTPUT.lod]"

in="$1"
out="${2:-${in%.*}.lod}"

for tool in od dd awk stat tr; do
  command -v "$tool" >/dev/null 2>&1 || die "required tool not found: $tool"
done

[ -f "$in" ] || die "input file not found: $in"
[ "$in" != "$out" ] || die "input and output must be different files"
if [ -e "$out" ] && [ "$force" -ne 1 ]; then
  die "output file already exists: $out (use -f to overwrite)"
fi

# od -tu2 / -tu4 use the byte order of the machine; the file is little-endian.
if [ "$(printf '\001\000' | od -An -tu2 | tr -d ' ')" != "1" ]; then
  die "this script must run on a little-endian machine (x86, x86_64, ...)"
fi

size=$(stat -c %s "$in")
[ "$size" -gt 128 ] || die "file is too small to be a Dell FWH file ($size bytes)"

# --- Dell header ------------------------------------------------------------
sig=$(dd if="$in" bs=1 count=8 2>/dev/null | tr -d '\000')
[ "$sig" = "    DELL" ] || die "no Dell signature at offset 0 - this is not a Dell FWH file (or it is already a LOD image)"

rev=$(dd if="$in" bs=1 skip=9 count=4 2>/dev/null | tr -cd '[:alnum:]')
count=$(od -An -tu1 -j63 -N1 "$in" | tr -d ' ')
{ [ "$count" -ge 1 ] && [ "$count" -le 64 ]; } || die "implausible number of model entries in header: $count"

header=$((64 + count * 48))
lodsize=$((size - header))
[ "$lodsize" -ge 64 ] || die "file ends inside the Dell header (header=$header, size=$size)"

note "Input file        : $in ($size bytes)"
note "Firmware revision : $rev"
note "Model entries     : $count"

found_model=0
i=0
while [ "$i" -lt "$count" ]; do
  model=$(dd if="$in" bs=1 skip=$((64 + i * 48 + 8)) count=40 2>/dev/null | tr -cd '[:alnum:]-')
  note "   - $model"
  if [ -n "$want_model" ] && [ "$model" = "$want_model" ]; then found_model=1; fi
  i=$((i + 1))
done

if [ -n "$want_model" ] && [ "$found_model" -ne 1 ]; then
  die "model $want_model is NOT listed in this firmware file - do not use it for that drive"
fi

note "Dell header       : $header bytes (0x$(printf '%X' "$header"))"
note "LOD image         : $lodsize bytes"

# --- checks on the LOD image -------------------------------------------------
[ $((lodsize % 512)) -eq 0 ] || die "LOD length $lodsize is not a multiple of 512 - header length is wrong for this file"

sum=$(od -An -v -tu2 -j"$header" -N64 "$in" | awk '{for(i=1;i<=NF;i++)s+=$i} END{print s%65536}')
[ "$sum" -eq 0 ] || die "LOD header checksum does not sum to 0 (got $sum) - unknown file layout, refusing to continue"

field=$(od -An -tu4 -j$((header + 36)) -N4 "$in" | tr -d ' ')
[ "$field" -eq "$lodsize" ] || die "length stored in the LOD header ($field) differs from the real length ($lodsize) - refusing to continue"

note "Check 1/3         : length is a multiple of 512            OK"
note "Check 2/3         : LOD header checksum                    OK"
note "Check 3/3         : stored length equals real length       OK"

# --- write and re-verify ------------------------------------------------------
dd if="$in" of="$out" bs="$header" skip=1 2>/dev/null

outsize=$(stat -c %s "$out")
[ "$outsize" -eq "$lodsize" ] || { rm -f "$out"; die "written file has the wrong size ($outsize), removed it"; }

outsum=$(od -An -v -tu2 -N64 "$out" | awk '{for(i=1;i<=NF;i++)s+=$i} END{print s%65536}')
outfield=$(od -An -tu4 -j36 -N4 "$out" | tr -d ' ')
{ [ "$outsum" -eq 0 ] && [ "$outfield" -eq "$outsize" ]; } || { rm -f "$out"; die "verification of the written file failed, removed it"; }

note "Output file       : $out ($outsize bytes)"
if command -v sha256sum >/dev/null 2>&1; then
  sha=$(sha256sum "$out" | awk '{print $1}')
  note "SHA-256           : $sha"
  if [ "$sha" = "$known_ga10_sha256" ]; then
    note "Known image       : yes - identical to the GA10 image tested in this guide"
  else
    note "Known image       : NO - this is not the GA10 image tested in this guide, double-check before flashing"
  fi
fi
note "Done. Nothing was flashed - see the README for the next step."
