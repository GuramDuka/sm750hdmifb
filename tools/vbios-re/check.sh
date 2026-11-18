#!/bin/sh
# Rebuild the SM750 board option ROM from the committed 16-bit reconstruction
# and verify it byte for byte. Opt-in: `make vbios-re`.
#
# The captured image is vendor material and is never committed, so this
# harness SKIPS (exit 77) when it is not present on the host.
#
# Environment:
#   VBIOS_ROM    path to the captured image (default below)
#   VBIOS_RE_OUT scratch directory for the generated source and image
set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
rom=${VBIOS_ROM:-/mega/tmp/sm750/vbios-01-00-0.bin}

if [ ! -f "$rom" ]; then
    echo "SKIP: captured ROM not present at $rom"
    exit 77
fi

exec python3 "$here/reencode.py" --rom "$rom" "$@"
