#!/usr/bin/env python3
"""Execution-trace harness for the SM750 board option ROM.

The reconstruction is already proven byte-identical to the capture, so the
remaining question is behavioural: does the rebuilt image execute the same
instructions as the captured one? This tool answers it by running both images
from the same reset state through the same CPU model and diffing the traces.

Two engines, both started at CS=0xC000 IP=0x1256 with the image loaded at
linear 0xC0000 and a 16-bit stack at SS=0 SP=0x7C00:

  qemu     qemu-system-i386, `-device loader,file=...,addr=0xc0000,
           force-raw=on`, paused with -S, driven over the gdb stub by a
           generated gdb command file that single-steps and prints CS:IP plus
           16 instruction bytes per step.
  unicorn  unicorn 2.x in UC_MODE_16, image mapped at 0xC0000, UC_HOOK_CODE for
           PC and bytes and UC_HOOK_INSN for IN/OUT, which the gdb stub cannot
           observe.

Neither machine has an SM750, so every port and MMIO access is recorded as
the write itself and nothing else; no device effect exists. Unicorn answers IN
with 0. Both engines therefore see a device that never responds: the ROM's PCI
configuration scan finishes without a match and the run ends at the
instruction bound with a `no progress` note, which is reported as such instead
of being called a completed boot.

Usage: trace.py --rom PATH [--engine both|qemu|unicorn] [--bound N]
                [--out DIR] [--port N] [--compare PATH2]
Exit 77 means SKIP: a required tool or the captured image is absent.
Exit 1 means the two images diverged, or an engine failed.
"""

import argparse
import hashlib
import json
import os
import re
import socket
import subprocess
import sys
import time

BASE = 0xC0000
SEG = 0xC000
LIMIT = BASE + 0x10000
ENTRY_IP = 0x1256
STACK_SP = 0x7C00
DEFAULT_ROM = '/mega/tmp/sm750/vbios-01-00-0.bin'
DEFAULT_OUT = '/mega/tmp/sm750/trace'
DEFAULT_PORT = 47127
DEFAULT_BOUND = 2000
LOOP_PERIOD_MAX = 32
LOOP_REPEAT = 64
SKIP = 77


def die(msg, code=1):
    print(msg)
    sys.exit(code)


def sha256(data):
    return hashlib.sha256(data).hexdigest()


# ---------------------------------------------------------------- decoding

class Decoder(object):
    """Capstone in 16-bit mode, addressed by linear address."""

    def __init__(self):
        import capstone
        self.cs = capstone
        self.md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_16)
        self.md.detail = True

    def decode(self, raw, linear):
        ins = next(self.md.disasm(bytes(raw), linear), None)
        if ins is None:
            return None
        return ins

    def step(self, idx, linear, raw):
        ins = self.decode(raw, linear)
        if ins is None:
            mnem, ops, size, branch = 'db', '0x%02x' % raw[0], 1, '-'
        else:
            mnem, ops, size = ins.mnemonic, ins.op_str, ins.size
            branch = self.branch(ins)
        return {
            'idx': idx,
            'cs': SEG,
            'ip': linear & 0xffff,
            'linear': linear,
            'bytes': bytes(raw[:size]).hex(),
            'mnemonic': mnem,
            'operands': ops,
            'branch': branch,
        }

    def branch(self, ins):
        cs = self.cs
        if not (ins.group(cs.CS_GRP_JUMP) or ins.group(cs.CS_GRP_CALL)):
            return '-'
        if not ins.operands:
            return '?'
        op = ins.operands[0]
        if op.type == cs.x86.X86_OP_IMM:
            return '0x%06x' % (op.imm & 0xfffff)
        return '?'


# --------------------------------------------------------- classification

def classify(steps):
    """Decide why the run ended and where the meaningful trace stops."""
    for i, s in enumerate(steps):
        if s['cs'] != SEG or not (BASE <= s['linear'] < LIMIT):
            return ('far-transfer', i,
                    'control left the ROM segment at step %d (linear 0x%06x)'
                    % (i, s['linear']))
    pcs = [s['linear'] for s in steps]
    n = len(pcs)
    for k in range(1, LOOP_PERIOD_MAX + 1):
        span = k * (LOOP_REPEAT + 1)
        if n < span:
            continue
        if all(pcs[i] == pcs[i - k] for i in range(n - k * LOOP_REPEAT, n)):
            stop = n - k * LOOP_REPEAT + k
            return ('loop', stop,
                    'repeated-PC cycle of %d instructions at 0x%05x-0x%05x '
                    'repeated %d times without progress'
                    % (k, min(pcs[-k:]), max(pcs[-k:]), LOOP_REPEAT))
    return ('bound', n, 'instruction bound reached')


# ---------------------------------------------------------------- trace text

def step_line(s):
    return ('%06d %04x:%04x lin=%06x bytes=%-20s %-8s %-24s branch=%s'
            % (s['idx'], s['cs'], s['ip'], s['linear'], s['bytes'],
               s['mnemonic'], s['operands'], s['branch']))


def io_line(e):
    return ('%06d io   %s port=%04x size=%d value=0x%x'
            % (e['idx'], e['kind'], e['port'], e['size'], e['value']))


def render(steps, ios):
    """One text line per event, ordered by step index, I/O after its step."""
    out = []
    by_idx = {}
    for e in ios:
        by_idx.setdefault(e['idx'], []).append(e)
    for s in steps:
        out.append(step_line(s))
        for e in by_idx.get(s['idx'], []):
            out.append(io_line(e))
    return out


# ---------------------------------------------------------------- engines

def trace_unicorn(img, bound, dec):
    import unicorn
    from unicorn import x86_const as xc

    uc = unicorn.Uc(unicorn.UC_ARCH_X86, unicorn.UC_MODE_16)
    uc.mem_map(0, 0x100000)
    uc.mem_write(BASE, img)
    for reg, val in ((xc.UC_X86_REG_CS, SEG), (xc.UC_X86_REG_EIP, ENTRY_IP),
                     (xc.UC_X86_REG_SS, 0), (xc.UC_X86_REG_SP, STACK_SP),
                     (xc.UC_X86_REG_DS, 0), (xc.UC_X86_REG_ES, 0),
                     (xc.UC_X86_REG_FS, 0), (xc.UC_X86_REG_GS, 0),
                     (xc.UC_X86_REG_EFLAGS, 0x2)):
        uc.reg_write(reg, val)

    steps, ios = [], []
    state = {'left': None, 'error': None}

    def on_code(uc_, address, size, _ud):
        if not (BASE <= address < LIMIT):
            state['left'] = address
            uc_.emu_stop()
            return
        raw = bytes(uc_.mem_read(address, 16))
        steps.append(dec.step(len(steps), address, raw))

    def on_in(uc_, port, size, _ud):
        ios.append({'idx': len(steps) - 1, 'kind': 'in', 'port': port,
                    'size': size, 'value': 0})
        return 0

    def on_out(uc_, port, size, value, _ud):
        ios.append({'idx': len(steps) - 1, 'kind': 'out', 'port': port,
                    'size': size, 'value': value & 0xffffffff})

    uc.hook_add(unicorn.UC_HOOK_CODE, on_code)
    uc.hook_add(unicorn.UC_HOOK_INSN, on_in, None, 1, 0, xc.UC_X86_INS_IN)
    uc.hook_add(unicorn.UC_HOOK_INSN, on_out, None, 1, 0, xc.UC_X86_INS_OUT)

    try:
        uc.emu_start(BASE + ENTRY_IP, 0, 0, bound)
    except unicorn.UcError as exc:
        state['error'] = str(exc)

    meta = {'error': state['error']}
    if state['left'] is not None:
        lin = state['left']
        meta['far'] = {'linear': lin, 'cs': (lin >> 4) & 0xffff,
                       'ip': lin & 0xf}
    return steps, ios, meta


GDB_SCRIPT = """set pagination off
set confirm off
set height 0
set width 0
target remote 127.0.0.1:%(port)d
set $cs = 0xc000
set $eip = 0x1256
set $ss = 0
set $sp = 0x7c00
set $ds = 0
set $es = 0
set $fs = 0
set $gs = 0
set $n = 0
while $n < %(bound)d
  printf "P %%d %%04x %%04x\\n", $n, ($cs), ($eip)
  x/16xb (($cs << 4) + $eip)
  si
  set $n = $n + 1
  if ($cs) != 0xc000
    printf "FAR %%04x %%04x\\n", ($cs), ($eip)
    loop_break
  end
end
printf "END %%d\\n", $n
detach
quit
"""


def port_free(port):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        s.connect(('127.0.0.1', port))
        return False
    except OSError:
        return True
    finally:
        s.close()


def wait_port(port, timeout=15.0):
    end = time.time() + timeout
    while time.time() < end:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        try:
            s.settimeout(0.2)
            s.connect(('127.0.0.1', port))
            return True
        except OSError:
            time.sleep(0.05)
        finally:
            s.close()
    return False


def trace_qemu(rom_path, bound, dec, workdir, port, tag):
    if not port_free(port):
        die('FATAL: gdb port %d is already in use; pass --port' % port)
    gdb_file = os.path.join(workdir, tag + '.gdb')
    with open(gdb_file, 'w') as fh:
        fh.write(GDB_SCRIPT % {'port': port, 'bound': bound})
    qlog = os.path.join(workdir, tag + '.qemu.log')

    cmd = ['qemu-system-i386', '-M', 'pc', '-m', '8', '-S',
           '-gdb', 'tcp:127.0.0.1:%d' % port,
           '-device', 'loader,file=%s,addr=0xc0000,force-raw=on' % rom_path,
           '-display', 'none', '-monitor', 'none', '-serial', 'none',
           '-no-reboot', '-no-shutdown']
    with open(qlog, 'wb') as log:
        # The log is the only record of the emulator invocation, so keep it.
        log.write((' '.join(cmd) + '\n').encode('ascii'))
        log.flush()
        proc = subprocess.Popen(cmd, stdout=log, stderr=subprocess.STDOUT)
    try:
        if not wait_port(port):
            die('FATAL: qemu gdb stub did not listen on port %d '
                '(see %s)' % (port, qlog))
        run = subprocess.run(['gdb', '-q', '-batch', '-x', gdb_file],
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                             timeout=600)
    except subprocess.TimeoutExpired as exc:
        die('FATAL: gdb did not finish within 600 s; partial transcript %s'
            % (exc.stdout.decode('ascii', 'replace')[-2000:]
               if exc.stdout else '(none)'))
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()
    text = run.stdout.decode('ascii', 'replace')
    with open(os.path.join(workdir, tag + '.gdb.out'), 'w') as fh:
        fh.write(text)
    if run.returncode != 0:
        die('FATAL: gdb exited %d; transcript %s'
            % (run.returncode, os.path.join(workdir, tag + '.gdb.out')))

    steps, meta, pend = [], {}, None
    for line in text.splitlines():
        m = re.match(r'^P (\d+) ([0-9a-f]{4}) ([0-9a-f]{4})$', line)
        if m:
            pend = (int(m.group(1)), int(m.group(2), 16), int(m.group(3), 16))
            continue
        if pend is not None:
            raw = re.findall(r'0x([0-9a-f]{2})', line.split(':', 1)[-1])
            if len(raw) >= 2:
                lin = (pend[1] << 4) + pend[2]
                steps.append(dec.step(pend[0], lin,
                                      bytes(int(b, 16) for b in raw)))
                pend = None
                continue
        m = re.match(r'^FAR ([0-9a-f]{4}) ([0-9a-f]{4})$', line)
        if m:
            cs, ip = int(m.group(1), 16), int(m.group(2), 16)
            meta['far'] = {'linear': (cs << 4) + ip, 'cs': cs, 'ip': ip}
        m = re.match(r'^END (\d+)$', line)
        if m:
            meta['end'] = int(m.group(1))
    if not steps:
        die('FATAL: qemu engine produced no steps; transcript %s'
            % os.path.join(workdir, tag + '.gdb.out'))
    for i, s in enumerate(steps):
        if s['idx'] != i:
            die('FATAL: qemu trace step indices are not contiguous at %d' % i)
    return steps, [], meta


ENGINES = ('qemu', 'unicorn')


def run_engine(engine, rom, img, bound, dec, workdir, port, tag):
    if engine == 'unicorn':
        return trace_unicorn(img, bound, dec)
    return trace_qemu(rom, bound, dec, workdir, port, tag)


STALL_MIN = 500


def stalled(steps):
    """Steps since the last instruction the trace had never executed before.

    A suffix with no new PC is a fact, not proof of an infinite loop, so it is
    reported as such: on this image the suffix is the PCI configuration poll,
    which needs a device to answer and has none here.
    """
    seen = set()
    last_new = -1
    for i, s in enumerate(steps):
        if s['linear'] not in seen:
            seen.add(s['linear'])
            last_new = i
    run = len(steps) - 1 - last_new
    if run < STALL_MIN:
        return None
    tail = [s['linear'] for s in steps[last_new + 1:]]
    return {'steps': run, 'after_step': last_new + 1,
            'new_pc': '0x%05x' % steps[last_new]['linear'],
            'distinct_pcs': len(set(tail)),
            'min': '0x%05x' % min(tail), 'max': '0x%05x' % max(tail)}


def emit(outdir, label, engine, rom, img, steps, ios, meta, bound):
    reason, stop, detail = classify(steps)
    if meta.get('far'):
        f = meta['far']
        reason = 'far-transfer'
        stop = len(steps)
        detail = ('control left the ROM segment: %04x:%04x linear 0x%05x'
                  % (f['cs'], f['ip'], f['linear']))
    if meta.get('error'):
        reason = 'error'
        detail = meta['error']
    kept_steps = steps[:stop]
    kept_ios = [e for e in ios if e['idx'] < stop]
    path = os.path.join(outdir, label + '.trace')
    with open(path, 'w') as fh:
        fh.write('# engine %s image %s sha256 %s\n'
                 % (engine, rom, sha256(img)))
        fh.write('# bound %d\n' % bound)
        fh.write('# stop %s: %s\n' % (reason, detail))
        for line in render(kept_steps, kept_ios):
            fh.write(line + '\n')
    summary = {
        'engine': engine,
        'rom': rom,
        'sha256': sha256(img),
        'size': len(img),
        'bound': bound,
        'steps_traced': len(steps),
        'steps': len(kept_steps),
        'stop': reason,
        'stop_detail': detail,
        'io_observable': engine == 'unicorn',
        'port_writes': len([e for e in kept_ios if e['kind'] == 'out']),
        'port_reads': len([e for e in kept_ios if e['kind'] == 'in']),
        'ports': sorted(set('%04x' % e['port'] for e in kept_ios)),
        'entered_0xc6065': any(s['linear'] == 0xc6065 for s in kept_steps),
        'distinct_pcs': len(set(s['linear'] for s in kept_steps)),
        'stalled_region': stalled(kept_steps),
        'trace': path,
    }
    with open(os.path.join(outdir, label + '.json'), 'w') as fh:
        json.dump(summary, fh, indent=2, sort_keys=True)
        fh.write('\n')
    return summary, steps, ios


def compare(engine, a, b):
    """Compare two full traces of one engine, report the first mismatch."""
    sa, ia = a
    sb, ib = b
    n = min(len(sa), len(sb))
    for i in range(n):
        if sa[i] != sb[i]:
            return False, i, (
                'step %d differs:\n    captured : %s\n    rebuilt  : %s'
                % (i, step_line(sa[i]), step_line(sb[i])))
    if len(sa) != len(sb):
        longer = 'captured' if len(sa) > len(sb) else 'rebuilt'
        return False, n, (
            'traces end at different lengths: captured %d, rebuilt %d; the '
            '%s trace has the extra step %s'
            % (len(sa), len(sb), longer,
               step_line((sa if len(sa) > len(sb) else sb)[n])))
    if ia != ib:
        nio = min(len(ia), len(ib))
        for i in range(nio):
            if ia[i] != ib[i]:
                return False, ia[i]['idx'], (
                    'port event %d differs:\n    captured : %s\n'
                    '    rebuilt  : %s' % (i, io_line(ia[i]), io_line(ib[i])))
        longer = 'captured' if len(ia) > len(ib) else 'rebuilt'
        tail = ia if len(ia) > len(ib) else ib
        return False, tail[nio]['idx'], (
            'port events differ in count: captured %d, rebuilt %d; the %s '
            'trace has extra %s'
            % (len(ia), len(ib), longer, io_line(tail[nio])))
    return True, n, 'identical for %d steps' % n


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument('--rom', default=os.environ.get('VBIOS_ROM', DEFAULT_ROM))
    ap.add_argument('--compare', default=os.environ.get('VBIOS_TRACE_COMPARE'))
    ap.add_argument('--engine', default='both', choices=('both',) + ENGINES)
    ap.add_argument('--bound', type=int,
                    default=int(os.environ.get('VBIOS_TRACE_BOUND',
                                               DEFAULT_BOUND)))
    ap.add_argument('--out', default=os.environ.get('VBIOS_TRACE_OUT',
                                                    DEFAULT_OUT))
    ap.add_argument('--port', type=int,
                    default=int(os.environ.get('VBIOS_TRACE_PORT',
                                               DEFAULT_PORT)))
    args = ap.parse_args(argv)

    if not os.path.isfile(args.rom):
        print('SKIP: captured ROM not present at %s' % args.rom)
        return SKIP
    for tool in ('qemu-system-i386', 'gdb'):
        from shutil import which
        if which(tool) is None:
            print('SKIP: %s not installed' % tool)
            return SKIP
    try:
        dec = Decoder()
    except ImportError:
        print('SKIP: python3 capstone not importable '
              '(PYTHONPATH=/mega/tmp/sm750/pylib)')
        return SKIP

    engines = list(ENGINES) if args.engine == 'both' else [args.engine]
    if 'unicorn' in engines:
        try:
            import unicorn  # noqa: F401
        except ImportError:
            print('NOTE: python3 unicorn not importable; engine unicorn '
                  'skipped, qemu alone must pass')
            engines.remove('unicorn')

    os.makedirs(args.out, exist_ok=True)
    with open(args.rom, 'rb') as fh:
        img = fh.read()
    other = None
    if args.compare:
        if not os.path.isfile(args.compare):
            die('FATAL: comparison image not present at %s' % args.compare)
        with open(args.compare, 'rb') as fh:
            other = fh.read()

    print('captured   %s %d bytes sha256 %s'
          % (args.rom, len(img), sha256(img)))
    if other is not None:
        print('rebuilt    %s %d bytes sha256 %s'
              % (args.compare, len(other), sha256(other)))

    failed = []
    for engine in engines:
        summaries = {}
        full = {}
        for label, rom, data, port in (
                ('captured', args.rom, img, args.port),
                ('rebuilt', args.compare, other, args.port + 1)):
            if data is None:
                continue
            tag = '%s-%s' % (engine, label)
            steps, ios, meta = run_engine(engine, rom, data, args.bound, dec,
                                          args.out, port, tag)
            summary, steps, ios = emit(args.out, tag, engine, rom, data,
                                       steps, ios, meta, args.bound)
            summaries[label] = summary
            full[label] = (steps, ios)
            print('engine %-7s %-8s steps=%-5d stop=%-12s %s 0xc6065=%s'
                  % (engine, label, summary['steps'], summary['stop'],
                     ('ports(out=%d in=%d)' % (summary['port_writes'],
                                               summary['port_reads']))
                     if summary['io_observable']
                     else 'ports=n/a (gdb stub cannot observe I/O)',
                     'yes' if summary['entered_0xc6065'] else 'no'))
            print('         %s' % summary['stop_detail'])
            if summary['stalled_region']:
                r = summary['stalled_region']
                print('         no progress: the %d steps after step %d '
                      'executed no new PC (%s); %d distinct PCs in %s-%s'
                      % (r['steps'], r['after_step'], r['new_pc'],
                         r['distinct_pcs'], r['min'], r['max']))
        if summaries['captured']['steps'] < 100:
            failed.append('%s: only %d steps traced (need >= 100)'
                          % (engine, summaries['captured']['steps']))
        if not summaries['captured']['entered_0xc6065']:
            failed.append('%s: trace never entered the nested routine at '
                          '0xc6065' % engine)
        if 'rebuilt' in full:
            ok, idx, detail = compare(engine, full['captured'],
                                      full['rebuilt'])
            if ok:
                print('compare %-7s MATCH: %d steps identical, %d port '
                      'events identical' % (engine, len(full['captured'][0]),
                                            len(full['captured'][1])))
            else:
                failed.append('%s: traces diverged (first divergence at step '
                              '%d)' % (engine, idx))
                print('compare %-7s DIVERGED at step %d' % (engine, idx))
                print('  context:')
                steps_a = full['captured'][0]
                for j in range(max(0, idx - 3), min(len(steps_a), idx + 3)):
                    mark = '>>' if j == idx else '  '
                    print('  %s captured %s' % (mark, step_line(steps_a[j])))
                print(detail)

    if failed:
        print('VERDICT: FAIL')
        for line in failed:
            print('  ' + line)
        return 1
    print('VERDICT: PASS')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
