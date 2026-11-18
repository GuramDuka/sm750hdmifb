#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Derive a cppcheck-friendly compile database from bear's output.

cppcheck cannot parse the kernel headers. Given the kbuild include paths it
bails out on include/asm-generic/bitsperlong.h:22 ("Inconsistent word size")
and include/linux/compiler_types.h:37 (__has_attribute in an #if), which leaves
5 of 975 checkers active and analyses nothing - a planted out-of-bounds write
in the driver goes unreported.

Dropping the kernel -I/-include/-Wp flags keeps the kbuild -D configuration
(which selects the driver code paths under test) and lets cppcheck analyse the
driver sources themselves. With this database 81 checkers are active and the
planted out-of-bounds write is reported; see docs/STATIC-ANALYSIS.md.
"""
import json
import sys

DROP_EXACT = {"-nostdinc", "-c"}
DROP_PREFIX = ("-I/usr/src/kernels", "-I/mega/tmp", "-Wp,", "-f", "-m", "-O",
               "-std=", "-W", "-D__KERNEL__")


def main(src, dst):
    with open(src, encoding="utf-8") as handle:
        entries = json.load(handle)
    out = []
    for entry in entries:
        args = ["cppcheck", "--enable=warning,performance,portability",
                # cppcheck cannot evaluate a function-like macro in #if, and
                # <linux/version.h> tests KERNEL_VERSION() that way.
                "-DKERNEL_VERSION(a,b,c)=(((a)<<16)+((b)<<8)+(c))"]
        pending = iter(entry["arguments"][1:])
        for arg in pending:
            if arg == "-include":
                next(pending, None)
                continue
            if arg in DROP_EXACT or arg.startswith(DROP_PREFIX):
                continue
            if arg.endswith(".c") or arg == entry["file"]:
                continue
            args.append(arg)
        args.append(entry["file"])
        out.append({"directory": entry["directory"], "file": entry["file"],
                    "arguments": args})
    with open(dst, "w", encoding="utf-8") as handle:
        json.dump(out, handle, indent=1)
    print("%d entries -> %s" % (len(out), dst))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
