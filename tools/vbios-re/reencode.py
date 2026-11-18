#!/usr/bin/env python3
"""Rebuild the SM750 option ROM from a 16-bit assembly reconstruction.

The captured image is 49152 bytes, loads at 0xC0000 and is never committed.
This tool derives a complete nasm source from it, assembles that source with
`nasm -f bin`, and then proves the result is the captured image again:

  * the rebuilt file is 49152 bytes;
  * its sha256 equals the captured digest;
  * a byte-for-byte comparison reports no difference;
  * for every code region the disassembly of both images is identical;
  * the ROM size byte, the PCIR image length and the ROM checksum byte are
    computed from the region table and the assembled image, and the build
    fails if a computed value differs from the captured byte.

Every instruction slot is decided in isolation: a candidate spelling is
assembled on its own at its own origin, so a slot that cannot be reproduced
cannot shift the decision made for its neighbours. Two byte-level
canonicalisations are then applied slot by slot, and only where the rewritten
bytes are exactly the captured bytes.

Usage: reencode.py [--rom PATH] [--out DIR] [--quiet]
Exit 77 means SKIP: the captured image is not present on this host.
"""

import argparse
import hashlib
import os
import re
import shutil
import subprocess
import sys

BASE = 0xC0000
DEFAULT_ROM = '/mega/tmp/sm750/vbios-01-00-0.bin'
DEFAULT_OUT = '/mega/tmp/sm750/t17/reconstruct'
SKIP = 77
SKIP_MSG = 'SKIP: captured ROM not present at %s'

# Header fields that the build computes instead of copying.
SIZE_OFF = 0x02          # ROM size in 512-byte blocks, one byte
IMAGE_LEN_OFF = 0x2C     # PCIR image length in 512-byte blocks, one word
CHECKSUM_OFF = 0x34      # whole-image checksum byte, sum of all bytes == 0

SZ = {'BYTE': 'b', 'WORD': 'w', 'DWORD': 'd', 'QWORD': 'q', 'TBYTE': 't'}
LONG = {'BYTE': 'byte', 'WORD': 'word', 'DWORD': 'dword', 'QWORD': 'qword',
        'TBYTE': 'tword', 'XMMWORD': 'oword'}
PREF = ('rep', 'repe', 'repz', 'repne', 'repnz', 'lock', 'data16', 'data32',
        'addr16', 'addr32')
SEGS = ('cs', 'ds', 'es', 'ss', 'fs', 'gs')
STR = ('movs', 'stos', 'lods', 'scas', 'cmps', 'ins', 'outs')
DSUF = ('sgdt', 'sidt', 'lgdt', 'lidt', 'sldt', 'str', 'lldt', 'ltr', 'smsw',
        'lmsw', 'verr', 'verw')
REGSZ = {'al': 'b', 'ax': 'w', 'eax': 'd', 'dx': 'w', 'edx': 'd',
         'cl': 'b', 'cx': 'w', 'ecx': 'd'}
NOSIZE = ('loop', 'loope', 'loopne', 'loopz', 'loopnz', 'jcxz')
STR_DFLT = {'movs': ('es', 'ds'), 'cmps': ('ds', 'es'), 'stos': ('es',),
            'scas': ('es',), 'ins': ('es',), 'lods': ('ds',),
            'outs': ('ds',)}

LEGACY_ORDER = [0x67, 0x66, 0xF3, 0xF2, 0xF0]
SEGBYTE = {0x26: 'es', 0x2e: 'cs', 0x36: 'ss', 0x3e: 'ds',
           0x64: 'fs', 0x65: 'gs'}
PREFIXES = set(LEGACY_ORDER) | set(SEGBYTE)
DIR_SWAP = {0x00: 0x02, 0x08: 0x0A, 0x10: 0x12, 0x18: 0x1A, 0x20: 0x22,
            0x28: 0x2A, 0x30: 0x32, 0x38: 0x3A, 0x84: 0x86, 0x88: 0x8A,
            0x89: 0x8B, 0x01: 0x03, 0x09: 0x0B, 0x11: 0x13, 0x19: 0x1B,
            0x21: 0x23, 0x29: 0x2B, 0x31: 0x33, 0x39: 0x3B, 0x85: 0x87}


def run(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    return r.returncode, r.stdout, r.stderr


def read_regions(path):
    """<kind> <start:04x> <end:04x> lines, contiguous over the whole image."""
    out = []
    for line in open(path):
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        kind, s, e = line.split()
        out.append((kind, int(s, 16), int(e, 16)))
    return out


def disasm(rom, start, end):
    """Instruction stream of one code region, with the byte columns merged."""
    rc, out, err = run(['objdump', '-D', '-b', 'binary', '-m', 'i8086',
                        '-M', 'intel', '-z', '--adjust-vma=0x%x' % BASE,
                        '--start-address=0x%x' % (BASE + start),
                        '--stop-address=0x%x' % (BASE + end), rom])
    if rc:
        raise RuntimeError(err)
    res = []
    for line in out.splitlines():
        m = re.match(r'^\s+([0-9a-f]+):\t(.*)$', line)
        if not m:
            continue
        off = int(m.group(1), 16) - BASE
        if off < start or off >= end:
            continue
        parts = m.group(2).split('\t', 1)
        hexpart = parts[0].strip()
        txt = parts[1].strip() if len(parts) > 1 else ''
        by = bytes.fromhex(hexpart.replace(' ', '')) if hexpart else b''
        if not by:
            continue
        if txt == '':
            # objdump wrapped the byte column onto a second line
            assert res and res[-1][0] + len(res[-1][1]) == off, hex(off)
            p = res[-1]
            res[-1] = (p[0], p[1] + by, p[2])
        else:
            res.append((off, by, txt))
    # objdump decodes a 66-prefixed far call as ptr16:32 and swallows the
    # next instruction's leading 66 9a; re-split the merged slot into the two
    # 6-byte transfers the vendor actually wrote.
    split, i = [], 0
    while i < len(res):
        off, by, txt = res[i]
        if (by[:2] == b'\x66\x9a' and len(by) == 8 and by[6:] == b'\x66\x9a'
                and i + 1 < len(res) and res[i + 1][0] == off + 8
                and len(res[i + 1][1]) == 4):
            split.append((off, by[:6], '\x00FAR'))
            split.append((off + 6, by[6:] + res[i + 1][1], '\x00FAR'))
            i += 2
            continue
        split.append((off, by, txt))
        i += 1
    return split


def split_pre(text):
    pre, t = [], text
    while True:
        m = re.match(r'^(\S+)\s+(.*)$', t)
        if not m:
            break
        w = m.group(1).lower()
        if w in PREF or (w in SEGS and not t.startswith(w + ':')):
            pre.append(w)
            t = m.group(2)
            continue
        break
    return pre, t


def fix_mem(t):
    t = re.sub(r'\b(BYTE|WORD|DWORD|QWORD|TBYTE|XMMWORD) PTR\s+',
               lambda m: LONG[m.group(1)] + ' ', t)
    t = re.sub(r'\b(byte|word|dword|qword|tword|oword) ([cdefgs]s):\[',
               r'\1 [\2:', t)
    t = re.sub(r'(?<!\[)\b([cdefgs]s):\[', r'[\1:', t)
    t = re.sub(r'\b(byte|word|dword|qword|tword|oword) ([cdefgs]s):(0x[0-9a-f]+)',
               r'\1 [\2:\3]', t)
    t = re.sub(r'(?<!\[)\b([cdefgs]s):(0x[0-9a-f]+)', r'[\1:\2]', t)
    t = re.sub(r'\bst\((\d)\)', r'st\1', t)
    t = re.sub(r'(?<![\w.])st\b(?!\d)', 'st0', t)
    return t


def str_variant(body):
    """`stos WORD PTR es:[di],ax` -> `stosw`.

    The es: destination of the string ops is implicit in the mnemonic, so only
    an override that differs from the architectural default becomes a prefix.
    """
    toks = body.upper().replace(',', ' ').split()
    mn, size, segs = toks[0].lower(), None, []
    for tk in toks[1:]:
        if tk in SZ:
            size = SZ[tk]
        m = re.match(r'^\[?([CDEFGS]S):', tk)
        if m:
            segs.append(m.group(1).lower())
        if tk.lower() in REGSZ and mn in ('lods', 'scas', 'stos', 'movs'):
            size = size or REGSZ[tk.lower()]
    name = mn + (size or 'b')
    pre = [seg for seg, d in zip(segs, STR_DFLT[mn]) if seg != d]
    return ' '.join(pre + [name])


def variants(text, want):
    if not text or text.startswith('('):
        return []
    pre, t = split_pre(text)
    npre = []
    for p in pre:
        if p in ('data16', 'addr16'):
            continue
        if p == 'data32':
            npre.append('o32')
        elif p == 'addr32':
            return []           # no 16-bit encoding exists for this prefix
        else:
            npre.append(p)
    if text == '\x00FAR':
        off = int.from_bytes(want[2:4], 'little')
        seg = int.from_bytes(want[4:6], 'little')
        return ['o32 call 0x%04x:0x%04x' % (seg, off)]
    mn = t.split()[0].lower()
    if mn in STR:
        return [' '.join(npre + [str_variant(fix_mem(t))])]
    if mn[:-1] in DSUF and mn[-1] in 'wd':
        if mn[-1] == 'd' and 'o32' not in npre:
            npre = npre + ['o32']
        t = mn[:-1] + t[len(mn):]
        mn = mn[:-1]
    if mn == 'pushd':
        if 'o32' not in npre:
            npre = npre + ['o32']
        t = 'push' + t[len('pushd'):]
        mn = 'push'
    body = fix_mem(t)
    if mn in ('les', 'lds'):
        # the far pointer's width is implied by the register pair; nasm
        # rejects an explicit dword/word keyword here
        body = re.sub(r'^(les|lds)\s+(\w+),\s*(dword|word)\s+', r'\1 \2,', body)
    tail = body[len(mn):].strip()
    if mn in NOSIZE:
        return [' '.join(npre + [body])]
    op = split_prefixes(want)[1]
    if op[:1] == b'\xeb' or 0x70 <= op[0] <= 0x7f or \
            op[:1] in (b'\xe0', b'\xe1', b'\xe2'):
        return [' '.join(npre + [mn, 'short', tail])]
    if op[:1] == b'\xe9' or (len(op) >= 2 and op[0] == 0x0f and
                             0x80 <= op[1] <= 0x8f):
        return [' '.join(npre + [mn, 'near', tail])]
    out = [' '.join(npre + [body])]
    imm = re.sub(r',\s*(0x[0-9a-f]+|-?\d+)$', r', strict word \1', body)
    if imm == body:
        # a lone immediate operand (`push 0xffff`) needs the keyword too,
        # otherwise nasm picks the sign-extended imm8 form
        imm = re.sub(r'^(\w+)\s+(0x[0-9a-f]+|-?\d+)$', r'\1 strict word \2',
                     body)
    if imm != body:
        out.append(' '.join(npre + [imm]))
    if mn in ('jmp', 'call'):
        far = re.sub(r'^(jmp|call)\s+(dword|word)\s+', r'\1 far ', body)
        if far != body:
            out.append(' '.join(npre + [far]))
    if 'ds:' in body:
        out.append(' '.join(npre + [body.replace('ds:', '')]))
    if mn == 'call':
        out.append(' '.join(npre + ['call', 'near', tail]))
    return out


def split_prefixes(b):
    i = 0
    while i < len(b) and b[i] in PREFIXES:
        i += 1
    return b[:i], b[i:]


def canon_order(b):
    pre, rest = split_prefixes(b)
    segs = [p for p in pre if p in SEGBYTE]
    legs = sorted([p for p in pre if p in LEGACY_ORDER], key=LEGACY_ORDER.index)
    return bytes(legs + segs) + rest


def swap_dir(b):
    pre, rest = split_prefixes(b)
    if len(rest) < 2 or rest[0] not in DIR_SWAP or rest[1] >> 6 != 3:
        return b
    reg, rm = (rest[1] >> 3) & 7, rest[1] & 7
    return pre + bytes([DIR_SWAP[rest[0]], 0xC0 | (rm << 3) | reg]) + rest[2:]


def alias_82(b):
    """0x82 is an alias of the 0x80 group; the vendor used 0x82."""
    pre, rest = split_prefixes(b)
    if rest[:1] == b'\x80':
        return pre + b'\x82' + rest[1:]
    return b


def alias_incdec(b):
    """0x40-0x4f is the short inc/dec; the vendor used the FF /0,/1 form."""
    pre, rest = split_prefixes(b)
    if len(rest) == 2 and 0x40 <= rest[0] <= 0x4F and \
            rest[1] == 0xC0 | (rest[0] & 7):
        return pre + bytes([0xFF, 0xC0 | ((0 if rest[0] < 0x48 else 1) << 3) |
                            (rest[0] & 7)])
    return b


def alias_shift(b):
    """/4 and /6 of the shift group are the same operation (shl == sal)."""
    pre, rest = split_prefixes(b)
    if len(rest) >= 2 and rest[0] in (0xC0, 0xC1, 0xD0, 0xD1, 0xD2, 0xD3):
        r = (rest[1] >> 3) & 7
        if r == 4:
            return pre + rest[:1] + bytes([(rest[1] & 0xC7) | (6 << 3)]) + \
                rest[2:]
    return b


def alias_lock(b):
    """lock and rep are order-free; the vendor put lock first."""
    pre, rest = split_prefixes(b)
    if len(pre) >= 2 and pre[0] in (0xF2, 0xF3) and pre[1] == 0xF0:
        return bytes([0xF0, pre[0]]) + pre[2:] + rest
    return b


def drop_o32(b):
    """A lone 0x66 on a 16-bit operand size is redundant."""
    if b[:1] == b'\x66' and b[1:2] != b'':
        return b[1:]
    return b


CANON = (canon_order, swap_dir, alias_82, alias_incdec, alias_shift,
         alias_lock, drop_o32,
         lambda x: canon_order(swap_dir(x)),
         lambda x: swap_dir(canon_order(x)),
         lambda x: alias_82(canon_order(x)),
         lambda x: canon_order(alias_82(x)),
         lambda x: alias_shift(canon_order(x)),
         lambda x: canon_order(alias_incdec(x)))


def canonical(got, want):
    for f in CANON:
        if f(got) == want:
            return f(got)
    return None


class Builder:
    def __init__(self, rom_path, work):
        self.rom_path = rom_path
        self.work = work
        self.cache = {}

    def probe(self, off, cand):
        key = (off, cand)
        if key in self.cache:
            return self.cache[key]
        src = os.path.join(self.work, 'probe.asm')
        out = os.path.join(self.work, 'probe.bin')
        with open(src, 'w') as fh:
            fh.write('bits 16\norg 0x%x\n%s\n' % (BASE + off, cand))
        rc, _, _ = run(['nasm', '-f', 'bin', '-o', out, src])
        res = open(out, 'rb').read() if rc == 0 else None
        self.cache[key] = res
        return res

    def assemble(self, lines, name):
        p = os.path.join(self.work, name)
        with open(p, 'w') as fh:
            fh.write('\n'.join(lines) + '\n')
        out = p[:-4] + '.bin'
        rc, _, err = run(['nasm', '-f', 'bin', '-o', out, p])
        if rc:
            raise RuntimeError('nasm: ' + err[:4000])
        return open(out, 'rb').read()


def emit_source(rom, regions, builder, overrides):
    """nasm source for the whole image; returns (lines, slots, code_bytes)."""
    lines = ['bits 16', 'org 0x%x' % BASE]
    slots, code_bytes = [], 0
    for kind, s, e in regions:
        lines.append('')
        lines.append('; %05x-%05x %s' % (s, e, kind))
        if kind == 'data':
            b = bytearray(rom[s:e])
            for off, val in overrides.items():
                if s <= off < e:
                    b[off - s] = val
            b = bytes(b)
            for i in range(0, len(b), 16):
                lines.append('db ' + ','.join('0x%02x' % x for x in b[i:i + 16]))
            continue
        code_bytes += e - s
        for off, by, txt in disasm(builder.rom_path, s, e):
            want = rom[off:off + len(by)]
            assert want == by, (hex(off), by.hex(), want.hex())
            kind_s, src = 'db', 'db ' + ','.join('0x%02x' % x for x in want)
            for cand in variants(txt, want):
                got = builder.probe(off, cand)
                if got is None:
                    continue
                if got[:len(want)] == want:
                    kind_s, src = 'exact', cand
                    break
                if len(got) == len(want) and canonical(got, want):
                    kind_s, src = 'canon', cand
                    break
            lines.append(src)
            slots.append([off, len(want), kind_s, txt, src])
    return lines, slots, code_bytes


def decode_text(path, s, e):
    """Disassembly text of one region, one entry per instruction."""
    return [(off, by, txt) for off, by, txt in disasm(path, s, e)]


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('--rom', default=os.environ.get('VBIOS_ROM', DEFAULT_ROM))
    ap.add_argument('--out', default=os.environ.get('VBIOS_RE_OUT',
                                                    DEFAULT_OUT))
    ap.add_argument('--quiet', action='store_true')
    args = ap.parse_args(argv)

    here = os.path.dirname(os.path.abspath(__file__))
    region_path = os.path.join(here, 'regions.txt')

    if not os.path.exists(args.rom):
        print(SKIP_MSG % args.rom)
        return SKIP
    for tool in ('objdump', 'nasm'):
        if shutil.which(tool) is None:
            print('FAIL: %s not found' % tool)
            return 1

    rom = open(args.rom, 'rb').read()
    regions = read_regions(region_path)
    os.makedirs(args.out, exist_ok=True)

    fails = []
    say = (lambda *a: None) if args.quiet else print

    def check(ok, label, detail=''):
        say('%-5s %s%s' % ('PASS' if ok else 'FAIL', label,
                           (' ' + detail) if detail else ''))
        if not ok:
            fails.append(label)
        return ok

    # The region table must tile the image with no gap and no overlap.
    total = len(rom)
    pos = 0
    for kind, s, e in regions:
        if s != pos or e <= s:
            check(False, 'region table contiguous at %05x' % pos)
            break
        pos = e
    else:
        check(pos == total, 'region table tiles %d bytes' % total,
              '%d regions' % len(regions))

    # Fields the build computes rather than copies.
    blocks = total // 512
    overrides = {SIZE_OFF: blocks & 0xFF,
                 IMAGE_LEN_OFF: blocks & 0xFF,
                 IMAGE_LEN_OFF + 1: (blocks >> 8) & 0xFF,
                 CHECKSUM_OFF: 0}
    check(total % 512 == 0, 'image is a whole number of 512-byte blocks',
          str(blocks))

    builder = Builder(args.rom, args.out)
    lines, slots, code_bytes = emit_source(rom, regions, builder, overrides)
    out = bytearray(builder.assemble(lines, 'reencode.asm'))
    check(len(out) == total, 'assembled size', str(len(out)))

    # Canonicalise the slots that nasm spells differently from the vendor.
    # Each rewrite is accepted only where it equals the captured bytes, so a
    # slot that cannot be canonicalised is reported instead of guessed.
    ncanon = 0
    for off, ln, kind_s, txt, src in slots:
        if kind_s == 'canon':
            want = rom[off:off + ln]
            c = canonical(bytes(out[off:off + ln]), want)
            if c is None:
                check(False, 'canonicalisation at %05x' % off, txt)
            else:
                out[off:off + ln] = c
                ncanon += 1

    # The checksum is computed from the rebuilt image, not from the ROM: the
    # byte is solved so that the whole image sums to 0 mod 256.
    out[CHECKSUM_OFF] = 0
    out[CHECKSUM_OFF] = (-sum(out)) & 0xFF
    computed = out[CHECKSUM_OFF]
    check(computed == rom[CHECKSUM_OFF], 'checksum byte %02x' % computed,
          'captured %02x' % rom[CHECKSUM_OFF])
    check(out[SIZE_OFF] == rom[SIZE_OFF], 'size byte %02x' % out[SIZE_OFF],
          'captured %02x' % rom[SIZE_OFF])
    image_len = out[IMAGE_LEN_OFF] | (out[IMAGE_LEN_OFF + 1] << 8)
    check(image_len == (rom[IMAGE_LEN_OFF] | (rom[IMAGE_LEN_OFF + 1] << 8)),
          'PCIR image length %04x' % image_len,
          'captured %02x%02x' % (rom[IMAGE_LEN_OFF + 1], rom[IMAGE_LEN_OFF]))
    check(sum(out) & 0xFF == 0, 'whole image sums to 0 mod 256')
    got = bytes(out)

    built = os.path.join(args.out, 'reencode.bin')
    with open(built, 'wb') as fh:
        fh.write(got)

    # Bit-exactness.
    diff = [i for i in range(min(len(got), total)) if got[i] != rom[i]]
    check(not diff, 'byte-for-byte comparison',
          '0 differing bytes' if not diff else
          '%d differ, first %s' % (len(diff), hex(diff[0])))
    sha_built = hashlib.sha256(got).hexdigest()
    sha_rom = hashlib.sha256(rom).hexdigest()
    check(sha_built == sha_rom, 'sha256', sha_built)

    # Per-code-region decode equality, independent of the byte comparison.
    insns = 0
    bad = 0
    for kind, s, e in regions:
        if kind != 'code':
            continue
        a = decode_text(built, s, e)
        b = decode_text(args.rom, s, e)
        insns += len(a)
        if a != b:
            bad += 1
            check(False, 'decode equality %05x-%05x' % (s, e))
    check(bad == 0, 'decode equality over all code regions',
          '%d instructions' % insns)

    # Coverage: bytes emitted from mnemonics over total code bytes.
    db_bytes = sum(s_[1] for s_ in slots if s_[2] == 'db')
    kinds = {}
    for s_ in slots:
        kinds[s_[2]] = kinds.get(s_[2], 0) + 1
    cov = 100.0 * (code_bytes - db_bytes) / code_bytes
    say('')
    say('slots %d %s' % (len(slots), kinds))
    say('code %d bytes, carried as data %d bytes' % (code_bytes, db_bytes))
    say('coverage %.2f percent (floor 85)' % cov)
    say('canonicalised slots %d' % ncanon)
    check(cov >= 85.0, 'coverage above floor', '%.2f' % cov)
    if not args.quiet:
        for off, ln, kind_s, txt, src in slots:
            if kind_s == 'db':
                say('residual %05x %d bytes: %s' % (off, ln, txt))

    say('')
    if fails:
        say('FAILED: %d check(s): %s' % (len(fails), ', '.join(fails)))
        return 1
    say('OK: rebuilt %s is byte-identical to %s' % (built, args.rom))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
