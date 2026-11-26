#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
# Self-tests for tools/sm750-pkg.sh, the helper installed as
# /usr/local/sbin/sm750-pkg and allowlisted in docs/ROOT-ACTIONS.md section 3.8.
#
# The helper is the only command the owner has to allowlist, and its sudoers
# entry matches any argument list (docs/ROOT-ACTIONS.md section 1 makes a
# version-independent rule impossible any other way), so its own argv and file
# checks are the whole security boundary. That boundary is what this gate
# pins: newest-pair selection, version agreement, symlink refusal, argv
# refusal, the unprivileged status path, the root requirement, the
# ownership/mode policy for the candidate files, and the A65 reload guard
# (refusal while the framebuffer vtconsole is bound, and the --force override).
#
# Everything that would touch the system is stubbed through a temporary PATH:
# dnf, dkms, rpm, modprobe and lsmod are shell scripts in $scratch/bin that
# append one line each to $SM750_TEST_LOG. The real build tree is never read
# (SM750_PKG_ROOT points at a fake tree) and no package is installed, removed
# or loaded. Real commands used: realpath, stat, id, grep.
#
# Exit 0 when every check passes, 1 otherwise.
set -uo pipefail
export TMPDIR=${TMPDIR:-/mega/tmp/sm750/tmp}

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
single=0
if [ "${1:-}" = "--single" ]; then
	single=1
	shift
fi
helper=${1:-$project_dir/tools/sm750-pkg.sh}

fail=0
bad() {
	printf 'FAIL: %s\n' "$*" >&2
	fail=1
}

scratch=$(mktemp -d "${TMPDIR}/sm750-pkg-check.XXXXXX")
trap 'rm -rf -- "$scratch"' EXIT
log=$scratch/calls.log
bin=$scratch/bin
mkdir -p "$bin"
: >"$log"

# --- stubs ------------------------------------------------------------------
# Every stub records its argv in $SM750_TEST_LOG, so a test can assert how
# many times it ran (the dkms double-print defect, and "status never calls
# dnf").
# write_stub NAME - the body comes on stdin, so its quoting stays literal.
write_stub() {
	cat >"$bin/$1"
	chmod 0755 "$bin/$1"
}

write_stub dnf <<'EOF'
#!/bin/sh
printf 'dnf %s\n' "$*" >>"$SM750_TEST_LOG"
printf 'stub-dnf %s\n' "$*"
exit 0
EOF
write_stub dkms <<'EOF'
#!/bin/sh
printf 'dkms %s\n' "$*" >>"$SM750_TEST_LOG"
printf 'sm750hdmifb/0.6.2, 7.3.4-100.fc43.x86_64, x86_64: installed\n'
exit 0
EOF
write_stub rpm <<'EOF'
#!/bin/sh
printf 'rpm %s\n' "$*" >>"$SM750_TEST_LOG"
printf 'sm750hdmifb-0.6.2-1.fc43.noarch\n'
exit 0
EOF
write_stub modprobe <<'EOF'
#!/bin/sh
printf 'modprobe %s\n' "$*" >>"$SM750_TEST_LOG"
exit 0
EOF
write_stub lsmod <<'EOF'
#!/bin/sh
printf 'lsmod %s\n' "$*" >>"$SM750_TEST_LOG"
printf 'sm750hdmidrm          192512  0\n'
exit 0
EOF

# run_helper ROOT ARGS... - invoke the helper with the stub PATH and a fake
# build tree. Output goes to stdout, the exit code is the helper's.
run_helper() {
	_root=$1
	shift
	PATH="$bin:$PATH" SM750_PKG_ROOT="$_root" SM750_TEST_LOG="$log" \
		sh "$helper" "$@"
}

# The fake-root runner keeps its uid-0 `id` in a separate directory: test f
# above must keep seeing the real uid, so the stub cannot live in $bin.
binroot=$scratch/bin-root
mkdir -p "$binroot"
cat >"$binroot/id" <<'EOF'
#!/bin/sh
case "${1:-}" in
-u) printf '0\n' ;;
*) exec /usr/bin/id "$@" ;;
esac
EOF
chmod 0755 "$binroot/id"

# run_helper_root VTCLASS ARGS... - as run_helper, but uid 0 and a fake
# vtconsole tree, so the reload guard can be exercised without root or sysfs.
run_helper_root() {
	_vt=$1
	shift
	PATH="$binroot:$bin:$PATH" SM750_PKG_ROOT="$scratch/absent" \
		SM750_VTCLASS="$_vt" SM750_TEST_LOG="$log" sh "$helper" "$@"
}

# make_rpm TREE RELPATH - a plain, empty file standing in for a built RPM.
make_rpm() {
	mkdir -p "$1/$(dirname -- "$2")"
	: >"$1/$2"
}

# expect_exit LABEL GOT WANT
expect_exit() {
	[ "$2" -eq "$3" ] || bad "$1: exit $2, expected $3"
}

# expect_in LABEL HAYSTACK NEEDLE
expect_in() {
	case $2 in
	*"$3"*) ;;
	*) bad "$1: output does not contain '$3'" ;;
	esac
}

# expect_not_in LABEL HAYSTACK NEEDLE
expect_not_in() {
	case $2 in
	*"$3"*) bad "$1: output unexpectedly contains '$3'" ;;
	esac
}

# count_calls CMD
count_calls() {
	grep -c "^$1 " "$log" || true
}

# --- a. newest pair out of three versions -----------------------------------
# 0.6.1, 0.6.2 and 0.6.3 are all present; 0.6.3 must be the selected pair.
tree=$scratch/newest
for _v in 0.6.1 0.6.2 0.6.3; do
	make_rpm "$tree/noarch" "sm750hdmifb-$_v-1.fc43.noarch.rpm"
	make_rpm "$tree/x86_64" "sm750hdmifb-tools-$_v-1.fc43.x86_64.rpm"
done
out=$(run_helper "$tree" status 2>&1)
expect_exit "a: status" $? 0
expect_in "a: driver pair" "$out" "newest pair: sm750hdmifb 0.6.3-1.fc43 "
expect_in "a: tools pair" "$out" "newest pair: sm750hdmifb-tools 0.6.3-1.fc43 "
# The driver is noarch and the tools package is arch-dependent
# (packaging/sm750hdmifb-tools.spec ships a compiled ELF), so the arch
# difference must not read as a release mismatch.
expect_not_in "a: mixed arch is not a release mismatch" "$out" "release mismatch"
expect_not_in "a: older driver not selected" "$out" "newest pair: sm750hdmifb 0.6.2"
expect_not_in "a: older tools not selected" "$out" "newest pair: sm750hdmifb-tools 0.6.1"
expect_exit "a: status must not install" "$(count_calls dnf)" 0
printf 'ok: a newest pair selection (0.6.3 of 0.6.1/0.6.2/0.6.3)\n'

# --- b. driver and tools version mismatch refused ---------------------------
tree=$scratch/mismatch
make_rpm "$tree/x86_64" "sm750hdmifb-0.6.3-1.fc43.x86_64.rpm"
make_rpm "$tree/x86_64" "sm750hdmifb-tools-0.6.2-1.fc43.x86_64.rpm"
out=$(run_helper "$tree" status 2>&1)
expect_exit "b: status" $? 0
expect_in "b: mismatch named" "$out" \
	"install would refuse: version mismatch: sm750hdmifb 0.6.3-1.fc43 vs sm750hdmifb-tools 0.6.2-1.fc43"
expect_not_in "b: no install would run" "$out" "install would run:"
expect_exit "b: status must not install" "$(count_calls dnf)" 0
printf 'ok: b version mismatch refused\n'

# --- c. symlinks refused ----------------------------------------------------
# c1: a tools RPM that is a symlink to a file outside the build tree.
tree=$scratch/symlink
make_rpm "$tree/noarch" "sm750hdmifb-0.6.3-1.fc43.noarch.rpm"
: >"$scratch/outside.rpm"
mkdir -p "$tree/noarch"
ln -s "$scratch/outside.rpm" \
	"$tree/noarch/sm750hdmifb-tools-0.6.3-1.fc43.noarch.rpm"
out=$(run_helper "$tree" status 2>&1)
expect_in "c1: symlink file refused" "$out" "install would refuse: refusing"
expect_in "c1: refused for being a symlink" "$out" "it is a symlink"
expect_not_in "c1: no install would run" "$out" "install would run:"
# c2: an arch subdirectory that is a symlink outside the build tree.
tree=$scratch/symlink-dir
mkdir -p "$tree" "$scratch/elsewhere"
ln -s "$scratch/elsewhere" "$tree/noarch"
out=$(run_helper "$tree" status 2>&1)
expect_in "c2: symlink dir refused" "$out" "not a build directory"
printf 'ok: c symlink file and symlink directory refused\n'

# --- d. unknown argument refused with exit 2 --------------------------------
out=$(run_helper "$scratch/newest" bogus 2>&1)
expect_exit "d: bogus subcommand" $? 2
expect_in "d: usage printed" "$out" "usage: sm750-pkg install | remove | status | reload"
out=$(run_helper "$scratch/newest" 2>&1)
expect_exit "d: no subcommand" $? 2
out=$(run_helper "$scratch/newest" status extra 2>&1)
expect_exit "d: extra argument" $? 2
expect_in "d: extra argument usage" "$out" "usage: sm750-pkg"
expect_exit "d: refused argv must not install" "$(count_calls dnf)" 0
printf 'ok: d unknown, missing and extra arguments refused with exit 2\n'

# --- e. status runs unprivileged -------------------------------------------
# The gate itself runs as uid 1005 on this host; the assertion is that status
# stays read-only and exits 0 with a missing build tree, no RPMs and no root.
if [ "$(id -u)" -eq 0 ]; then
	printf 'SKIP: e status unprivileged (this gate is running as root)\n'
else
	out=$(run_helper "$scratch/absent" status 2>&1)
	st=$?
	expect_exit "e: status as uid $(id -u)" "$st" 0
	expect_in "e: status reports the missing tree" "$out" "build tree $scratch/absent is missing"
	expect_in "e: dkms section" "$out" "== dkms status"
	expect_exit "e: status must not install" "$(count_calls dnf)" 0
	printf 'ok: e status exits 0 unprivileged (uid %s)\n' "$(id -u)"
fi

# --- f. install refuses without root ---------------------------------------
if [ "$(id -u)" -eq 0 ]; then
	printf 'SKIP: f install without root (this gate is running as root)\n'
else
	out=$(run_helper "$scratch/newest" install 2>&1)
	st=$?
	expect_exit "f: install as uid $(id -u)" "$st" 1
	expect_in "f: root required" "$out" "install needs root"
	expect_exit "f: refused install must not call dnf" "$(count_calls dnf)" 0
	printf 'ok: f install refuses without root (exit 1, dnf not called)\n'
fi

# --- g. status executes dkms exactly once ----------------------------------
# Regression: the helper used to run `dkms status` twice, once through run()
# and once to test the exit code, so every dkms row appeared twice in the
# owner's transcript (field report m00065).
: >"$log"
out=$(run_helper "$scratch/newest" status 2>&1)
expect_exit "g: status" $? 0
expect_exit "g: dkms invoked once" "$(count_calls dkms)" 1
_lines=$(printf '%s\n' "$out" | grep -c 'sm750hdmifb/0.6.2, 7.3.4-100.fc43.x86_64, x86_64: installed')
expect_exit "g: dkms output printed once" "$_lines" 1
printf 'ok: g status invokes dkms exactly once\n'

# --- h. missing tools RPM names both halves and the build hint -------------
tree=$scratch/no-tools
make_rpm "$tree/noarch" "sm750hdmifb-0.6.3-1.fc43.noarch.rpm"
out=$(run_helper "$tree" status 2>&1)
expect_in "h: selected driver named" "$out" \
	"selected sm750hdmifb 0.6.3-1.fc43 ($tree/noarch/sm750hdmifb-0.6.3-1.fc43.noarch.rpm)"
expect_in "h: absent tools named" "$out" "no sm750hdmifb-tools RPM is present"
expect_in "h: build hint" "$out" "rpmbuild -ba"
expect_in "h: both specs in the hint" "$out" \
	"packaging/sm750hdmifb.spec packaging/sm750hdmifb-tools.spec"
expect_not_in "h: no install would run" "$out" "install would run:"
printf 'ok: h missing tools RPM names both halves and the build hint\n'

# --- i. ownership and mode policy ------------------------------------------
# The RPMs are built by the unprivileged owner of this tree, so they are owned
# by the invoking uid, not root. install and status share find_pair, so status
# is the unprivileged way to pin which pair install would select.
tree=$scratch/owner
make_rpm "$tree/noarch" "sm750hdmifb-0.6.3-1.fc43.noarch.rpm"
make_rpm "$tree/x86_64" "sm750hdmifb-tools-0.6.3-1.fc43.x86_64.rpm"
chmod 0755 "$tree" "$tree/noarch" "$tree/x86_64"
drv=$tree/noarch/sm750hdmifb-0.6.3-1.fc43.noarch.rpm
tools=$tree/x86_64/sm750hdmifb-tools-0.6.3-1.fc43.x86_64.rpm
chmod 0644 "$drv" "$tools"
out=$(run_helper "$tree" status 2>&1)
expect_exit "i1: status" $? 0
expect_in "i1: invoking uid and 0644 selected for install" "$out" \
	"install would run: dnf install -y --setopt=gpgcheck=True $drv $tools"
expect_not_in "i1: no refusal" "$out" "install would refuse"
# i2: the same pair with a group/other-writable file is refused.
chmod 0666 "$drv"
out=$(run_helper "$tree" status 2>&1)
expect_exit "i2: status" $? 0
expect_in "i2: 0666 file refused" "$out" \
	"refusing $drv: mode 666 is writable by group or others"
expect_not_in "i2: no install would run" "$out" "install would run:"
# i3: a group-writable containing directory is refused even for a 0644 file.
chmod 0644 "$drv"
chmod 0775 "$tree/x86_64"
out=$(run_helper "$tree" status 2>&1)
expect_exit "i3: status" $? 0
expect_in "i3: group-writable directory refused" "$out" \
	"refusing $tools: containing directory $tree/x86_64 is writable by group or others (mode 775)"
expect_not_in "i3: no install would run" "$out" "install would run:"
# i4: another local account reported as the invoker (SUDO_UID) must not be able
# to get the builder's file installed. The fixture is coder-owned; only the
# reported invoker changes. Unprivileged-only: as root the fixture is
# root-owned and accepted by the root branch.
if [ "$(id -u)" -eq 0 ]; then
	printf 'SKIP: i4 foreign invoking uid (this gate is running as root)\n'
else
	chmod 0755 "$tree/x86_64"
	out=$(PATH="$bin:$PATH" SUDO_UID=4242 SM750_PKG_ROOT="$tree" \
		SM750_TEST_LOG="$log" sh "$helper" status 2>&1)
	expect_in "i4: foreign invoking uid refused" "$out" \
		"refusing $drv: owned by uid $(id -u), not root or the invoking user (uid 4242)"
	expect_not_in "i4: no install would run" "$out" "install would run:"
fi
printf 'ok: i ownership and mode policy (invoking uid accepted, 0666 file and 0775 directory refused, foreign uid refused)\n'

# --- j. A65 reload guard ----------------------------------------------------
# A hot reload while the framebuffer vtconsole held the panel wedged the module
# in Unloading (refcount -1) on 2026-11-26 (A65). reload must refuse in that
# state, --force must be the only way past it, and the console's name is part
# of the match: a bound VGA+ console is not this guard.
vtroot=$scratch/vt
mkdir -p "$vtroot/vtcon0" "$vtroot/vtcon1"
printf '(S) VGA+\n' >"$vtroot/vtcon0/name"
printf '0\n' >"$vtroot/vtcon0/bind"
printf '(M) frame buffer device\n' >"$vtroot/vtcon1/name"
printf '1\n' >"$vtroot/vtcon1/bind"
refusal="sm750-pkg: refusing to unload: the framebuffer vtconsole is still bound (A65: a hot reload in that state wedged the module in Unloading on 2026-11-26). Run 'sm750-vt off' first, or pass --force if you accept the risk."
: >"$log"
out=$(run_helper_root "$vtroot" reload 2>&1)
st=$?
expect_exit "j1: bound fbcon reload" "$st" 1
expect_in "j1: refusal text" "$out" "$refusal"
expect_exit "j1: refused reload must not call modprobe" \
	"$(count_calls modprobe)" 0
# --force proceeds, states that it does, and unloads before it loads.
: >"$log"
out=$(run_helper_root "$vtroot" reload --force 2>&1)
st=$?
expect_exit "j2: forced reload" "$st" 0
expect_in "j2: force line" "$out" "sm750-pkg: unloading anyway (--force)"
expect_exit "j2: unload then load" "$(count_calls modprobe)" 2
_first=$(grep '^modprobe ' "$log" | head -n 1)
expect_in "j2: unload first" "$_first" "modprobe -r sm750hdmidrm"
# Only the framebuffer console's name is the guard: a bound VGA+ console and a
# detached fbcon both reload normally.
printf '1\n' >"$vtroot/vtcon0/bind"
printf '0\n' >"$vtroot/vtcon1/bind"
: >"$log"
out=$(run_helper_root "$vtroot" reload 2>&1)
st=$?
expect_exit "j3: bound non-fbcon console reloads" "$st" 0
expect_not_in "j3: no refusal" "$out" "refusing to unload"
expect_exit "j3: reload proceeds" "$(count_calls modprobe)" 2
printf 'ok: j A65 reload guard (bound fbcon refused, --force overrides, name is part of the match)\n'

if [ "$fail" -ne 0 ]; then
	printf 'sm750-pkg self-tests failed\n' >&2
	exit 1
fi
if [ "$single" -eq 1 ]; then
	printf 'sm750-pkg self-tests passed (10 groups, --single: %s)\n' "$helper"
	exit 0
fi

# --- planted controls -------------------------------------------------------
# Each control deletes one PROPERTY and keeps the sentence that explains it, so
# a gate that passes after the mutation is a gate that was not checking it.
control() {
	_name=$1
	_mutator=$2
	_planted=$scratch/planted-$_name.sh
	cp "$project_dir/tools/sm750-pkg.sh" "$_planted"
	chmod 0755 "$_planted"
	if ! "$_mutator" "$_planted"; then
		printf 'FAIL: negative control %s: mutator did not apply\n' "$_name" >&2
		fail=1
		return 1
	fi
	_err=$scratch/planted-$_name.err
	if bash "$0" --single "$_planted" >/dev/null 2>"$_err"; then
		printf 'FAIL: negative control %s was accepted\n' "$_name" >&2
		fail=1
		return 1
	fi
	[ -s "$_err" ] || {
		printf 'FAIL: negative control %s failed without a reason\n' \
			"$_name" >&2
		fail=1
		return 1
	}
	printf 'negative control %s: rejected: %s\n' \
		"$_name" "$(head -n 1 "$_err")"
}

# (a) guard removed entirely, call and function.
mut_guard_removed() {
	python3 - "$1" <<'PY'
import sys

path = sys.argv[1]
text = open(path).read()
call = "\treload_guard\n"
assert text.count(call) == 1, "guard call count"
text = text.replace(call, "", 1)
start = text.index("reload_guard() {\n")
end = text.index("\n}\n", start) + len("\n}\n")
open(path, "w").write(text[:start] + text[end:])
PY
}

# (b) guard matches only bind=1 without checking the console name.
mut_bind_only() {
	python3 - "$1" <<'PY'
import sys

path = sys.argv[1]
text = open(path).read()
old = '\t\t*"(M) frame buffer device"*) return 0 ;;\n'
assert text.count(old) == 1, "name match count"
open(path, "w").write(text.replace(old, "\t\t*) return 0 ;;\n", 1))
PY
}

# (c) --force accepted but never printed.
mut_force_silent() {
	python3 - "$1" <<'PY'
import sys

path = sys.argv[1]
text = open(path).read()
old = '\t\tsay "$PROG: unloading anyway (--force)"\n'
assert text.count(old) == 1, "force say count"
open(path, "w").write(text.replace(old, "", 1))
PY
}

control guard-removed mut_guard_removed
control name-unchecked mut_bind_only
control force-silent mut_force_silent

if [ "$fail" -ne 0 ]; then
	printf 'sm750-pkg self-tests failed\n' >&2
	exit 1
fi
printf 'sm750-pkg self-tests passed (10 groups: selection, version pair, symlinks, argv, unprivileged status, root gate, single dkms call, missing tools, ownership/mode, A65 reload guard)\n'
