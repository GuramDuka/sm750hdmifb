#!/bin/sh
# Trace the SM750 board option ROM by execution and compare the captured image
# with the reconstruction this tree generates. Opt-in: `make vbios-trace`.
#
# Both engines start the CPU at CS=0xC000 IP=0x1256 with the image at linear
# 0xC0000 and a 16-bit stack at SS=0 SP=0x7C00:
#   qemu     qemu-system-i386, `-device loader,file=...,addr=0xc0000,
#            force-raw=on`, paused with -S, single-stepped over the gdb stub by
#            a generated gdb command file.
#   unicorn  unicorn 2.x in 16-bit mode with UC_HOOK_CODE and IN/OUT hooks.
# No emulated machine has an SM750, so a port or MMIO write is recorded as the
# write and nothing else; there is no device effect to observe.
#
# The captured image is vendor material and is never committed, so this
# harness SKIPS (exit 77) when it is not present on the host, and also when
# qemu-system-i386, gdb or the rootless capstone are missing.
#
# Environment:
#   VBIOS_ROM          captured image (default below)
#   VBIOS_TRACE_OUT    scratch directory for traces and the rebuilt image
#   VBIOS_TRACE_BOUND  instruction bound per run (default 2000)
#   VBIOS_TRACE_PORT   first gdb port of the pair (default 47127)
#   VBIOS_PYLIB        rootless capstone/unicorn prefix (default below)
set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
rom=${VBIOS_ROM:-/mega/tmp/sm750/vbios-01-00-0.bin}
out=${VBIOS_TRACE_OUT:-/mega/tmp/sm750/trace}
pylib=${VBIOS_PYLIB:-/mega/tmp/sm750/pylib}

if [ ! -f "$rom" ]; then
    echo "SKIP: captured ROM not present at $rom"
    exit 77
fi

for tool in qemu-system-i386 gdb python3; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "SKIP: $tool not installed"
        exit 77
    fi
done

if [ -d "$pylib" ]; then
    PYTHONPATH="$pylib${PYTHONPATH:+:$PYTHONPATH}"
    export PYTHONPATH
fi
if ! python3 -c 'import capstone' >/dev/null 2>&1; then
    echo "SKIP: python3 capstone not importable (VBIOS_PYLIB=$pylib)"
    exit 77
fi

mkdir -p "$out/reconstruct"
# Compare against the reconstruction produced by the committed model now, not
# against whatever an earlier run left in a scratch directory.
if ! python3 "$here/reencode.py" --rom "$rom" --out "$out/reconstruct" \
        --quiet; then
    rc=$?
    if [ "$rc" -eq 77 ]; then
        echo "SKIP: captured ROM not present at $rom"
        exit 77
    fi
    echo "FAIL: the reconstruction did not rebuild; see the message above"
    exit "$rc"
fi

exec python3 "$here/trace.py" --rom "$rom" --out "$out" \
    --compare "$out/reconstruct/reencode.bin" "$@"