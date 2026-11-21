#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
# Rootless verification of packaging/sm750hdmifb.spec.
#
# Asserts: the spec builds from a fresh _topdir, the metadata and scriptlet
# order are as designed, %files matches the ship/no-ship decision list, the
# dkms sandbox compiles a real .ko (dkms install itself is root-only), the
# missing-headers branch warns without a non-zero exit, and the %posttrans
# stale-registration purge runs before the build loop, removes every other
# registered version of this module name while leaving the installed version
# and other module names alone, and deletes a registration tree dkms cannot
# unregister because its dkms.conf is gone (A37) - including when one removal
# fails (dkms exit 4): the purge then warns, keeps exit 0 and continues with
# the remaining versions. A version that is not a plain release token never
# reaches a path. Also asserts that dkms.conf carries no directive dkms 3.4.4
# reports as deprecated (A38), and that the console helper prints its
# zero-frame hint only for the zero-frame crc32 (A39).
# Root-only install assertions are skipped with a printed
# reason (docs/evidence/EVIDENCE-GAPS.md, GAP-B7).
#
# Writes its logs to docs/evidence/packaging/ by default; override with
# SM750_RPM_EVIDENCE. Scratch stays under /mega/tmp/sm750/t6 and never touches
# $HOME.
set -euo pipefail
export TMPDIR=${TMPDIR:-/mega/tmp/sm750/tmp}

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
spec=$project_dir/packaging/sm750hdmifb.spec
name=sm750hdmifb
module=sm750hdmidrm
version=0.6.2
kernel=$(uname -r)
arch=$(uname -m)
cc=/usr/bin/gcc
work=${SM750_RPM_WORK:-/mega/tmp/sm750/t6}
topdir=$work/rpmbuild
dkms_root=$work/dkms
evidence=${SM750_RPM_EVIDENCE:-$project_dir/docs/evidence/packaging}

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}
skip() {
	printf 'SKIP: %s\n' "$*"
}
note() {
	printf 'OK: %s\n' "$*"
}
log_header() {
	printf '# utc: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
	printf '# running kernel: %s\n' "$kernel"
	printf '# uid: %s\n' "$(id -u)"
	printf '# command: %s\n' "$*"
	printf '# workdir: %s\n\n--- output ---\n'
}

[ "$(id -u)" -eq 0 ] &&
	fail "run unprivileged: this test must never touch the system package database"
[ -f "$spec" ] || fail "missing $spec"
[ -x "$cc" ] || fail "missing $cc"
[ -e "$HOME/rpmbuild" ] &&
	fail "unexpected $HOME/rpmbuild: this test must not write to \$HOME"
git -C "$project_dir" rev-parse --git-dir >/dev/null 2>&1 ||
	fail "the tracked-only source tarball needs a git checkout"

# ASCII-only constraint for the spec and the test itself.
for file in "$spec" "$0"; do
	LC_ALL=C grep -nP '[^\x00-\x7F]' "$file" &&
		fail "non-ASCII byte in $file"
done

mkdir -p "$evidence"
rm -rf -- "$topdir" "$dkms_root" "$work/payload" "$work/posttrans"
mkdir -p "$topdir"/{SOURCES,SPECS,BUILD,BUILDROOT,RPMS,SRPMS}

# --- source payload: the tracked tree minus the development-only dirs -------
# Same rule as build-package.sh; the source archive is the DKMS payload. The
# list itself is declared once, in packaging/source-excludes.sh (defect A29).
# shellcheck source=../packaging/source-excludes.sh
. "$project_dir/packaging/source-excludes.sh"
mapfile -t exclude_pathspecs < <(sm750_dev_only_pathspecs)
source_archive=$topdir/SOURCES/$name-$version-source.tar.gz
tracked_list=$(mktemp "${TMPDIR}/sm750-rpm-tracked.XXXXXX")
trap 'rm -f -- "$tracked_list"' EXIT
git -C "$project_dir" ls-files -z -- . "${exclude_pathspecs[@]}" \
	>"$tracked_list"
tar -C "$project_dir" -czf "$source_archive" \
	--transform="s|^|$name-$version/|" --null -T "$tracked_list"
tar -tzf "$source_archive" | sed 's|/$||' | sort >"$work/tarball.list"
git -C "$project_dir" ls-files -- . "${exclude_pathspecs[@]}" |
	sed "s|^|$name-$version/|" | sort >"$work/tracked.list"
diff -u "$work/tracked.list" "$work/tarball.list" ||
	fail "source archive is not the tracked tree"
note "source payload matches git ls-files ($(wc -l <"$work/tracked.list") files)"

# --- build ------------------------------------------------------------------
{
	log_header "rpmbuild -ba --define '_topdir $topdir' $spec"
	rpmbuild -ba --define "_topdir $topdir" "$spec"
} >"$evidence/01-rpmbuild.log" 2>&1 || {
	tail -n 40 "$evidence/01-rpmbuild.log" >&2
	fail "rpmbuild -ba failed (see $evidence/01-rpmbuild.log)"
}
srpm=$(find "$topdir/SRPMS" -name "$name-$version-*.src.rpm" | head -n 1)
rpm_file=$(find "$topdir/RPMS/noarch" -name "$name-$version-*.noarch.rpm" |
	head -n 1)
[ -n "$srpm" ] || fail "no SRPM produced"
[ -n "$rpm_file" ] || fail "no noarch RPM produced"
[ "$(find "$topdir/SRPMS" -name '*.src.rpm' | wc -l)" -eq 1 ] ||
	fail "expected exactly one SRPM"
[ "$(find "$topdir/RPMS/noarch" -name '*.rpm' | wc -l)" -eq 1 ] ||
	fail "expected exactly one noarch RPM"
note "rpmbuild -ba exit 0: $(basename "$srpm"), $(basename "$rpm_file")"

# --- metadata ---------------------------------------------------------------
buildrequires=$(rpmspec -q --buildrequires "$spec")
printf '%s\n' "$buildrequires" | sort |
	diff -u <(printf 'dkms\ngcc\nmake\nrpm-build\n') - ||
	fail "BuildRequires are not exactly rpm-build, dkms, make, gcc"
[ "$(rpmspec -q --qf '%{VERSION}' "$spec")" = "$version" ] ||
	fail "spec Version is not $version"
[ "$(rpm -qp --qf '%{ARCH}' "$rpm_file")" = noarch ] ||
	fail "built package is not noarch"
[ "$(rpm -qp --qf '%{LICENSE}' "$rpm_file")" = GPL-2.0-only ] ||
	fail "unexpected License tag"
for tag in 'Requires: *dkms' 'Requires\(post\): *dkms' \
	'Requires\(post\): *kmod' 'Requires\(preun\): *dkms'; do
	grep -Eq "^$tag\$" "$spec" || fail "spec is missing '$tag'"
done
# rpm -qpR loses the scriptlet qualifier but keeps one entry per tag, so three
# "dkms" lines prove the runtime, %post and %preun requirements all exist.
[ "$(rpm -qpR "$rpm_file" | grep -cx dkms)" -eq 3 ] ||
	fail "expected three dkms requirements (runtime, post, preun)"
[ "$(rpm -qpR "$rpm_file" | grep -cx kmod)" -eq 1 ] ||
	fail "expected one kmod requirement (post)"
{
	log_header "rpm -qpR $rpm_file; rpmspec -q --buildrequires; requires"
	printf '%s\n' '--- rpm -qpR (binary) ---'
	rpm -qpR "$rpm_file"
	printf '%s\n' '--- rpm -qpR (srpm) ---'
	rpm -qpR "$srpm"
	printf '%s\n' '--- rpmspec -q --buildrequires ---'
	printf '%s\n' "$buildrequires"
	printf '%s\n' '--- rpmspec -q --requires ---'
	rpmspec -q --requires "$spec"
} >"$evidence/04-rpm-qpR.log" 2>&1
note "dependencies: BuildRequires 4, runtime dkms, post dkms+kmod, preun dkms"

# --- scriptlets -------------------------------------------------------------
postin=$(rpm -qp --qf '%{POSTIN}' "$rpm_file")
posttrans=$(rpm -qp --qf '%{POSTTRANS}' "$rpm_file")
preun=$(rpm -qp --qf '%{PREUN}' "$rpm_file")
postun=$(rpm -qp --qf '%{POSTUN}' "$rpm_file")
[ -n "$postin" ] || fail "%post is empty"
[ -n "$posttrans" ] || fail "%posttrans is empty"
[ -n "$preun" ] || fail "%preun is empty"
case "$postun" in
	'' | '(none)') ;;
	*) fail "%postun must not be used" ;;
esac

printf '%s\n' "$postin" | grep -F 'dkms add' >/dev/null ||
	fail "%post does not run dkms add"
printf '%s\n' "$postin" | grep -F '[ "$1" -eq 1 ]' >/dev/null ||
	fail "%post lacks the --rpm_safe_upgrade \$1 == 1 guard"
printf '%s\n' "$postin" | grep -F 'dkms build' >/dev/null &&
	fail "%post must not build (headers may be absent)"
printf '%s\n' "$preun" | grep -F 'dkms remove' >/dev/null ||
	fail "%preun does not run dkms remove"
printf '%s\n' "$preun" | grep -F '[ "$1" -eq 0 ]' >/dev/null ||
	fail "%preun lacks the --rpm_safe_upgrade \$1 == 0 guard"
printf '%s\n' "$posttrans" | grep -F 'dkms build' >/dev/null ||
	fail "%posttrans does not run dkms build"
printf '%s\n' "$posttrans" | grep -F 'dkms install' >/dev/null ||
	fail "%posttrans does not run dkms install"
printf '%s\n' "$posttrans" | grep -F 'depmod -a' >/dev/null ||
	fail "%posttrans does not run depmod -a"
build_line=$(printf '%s\n' "$posttrans" |
	grep -nE '^[[:space:]]*dkms build ' | head -n 1 | cut -d: -f1)
install_line=$(printf '%s\n' "$posttrans" |
	grep -nE '^[[:space:]]*dkms install ' | head -n 1 | cut -d: -f1)
[ "$build_line" -lt "$install_line" ] ||
	fail "dkms install is not sequenced after dkms build"

# Stale-registration purge (docs/PACKAGING-RPM.md section 4). Releases before
# 0.6.0 left other versions of this module name registered against the same
# /extra destination path, so the purge must exist, must be scoped to this
# module name, must never remove the version being installed, and must run
# BEFORE the build loop: "dkms install" first uninstalls the older registered
# version for the same kernel, so on a host where that registration is broken
# (source/ symlink dangling) the install aborts with "Error! Could not locate
# dkms.conf file." and never installs the new version (defect A37). A purge
# placed after the loop runs when the damage is already done.
purge_marker='removing stale DKMS registration'
printf '%s\n' "$posttrans" | grep -F "$purge_marker" >/dev/null ||
	fail "%posttrans has no stale-registration purge"
purge_line=$(printf '%s\n' "$posttrans" |
	grep -nF "$purge_marker" | head -n 1 | cut -d: -f1)
build_loop_line=$(printf '%s\n' "$posttrans" |
	grep -nE '^[[:space:]]*for kernel_dir in ' | head -n 1 | cut -d: -f1)
[ -n "$build_loop_line" ] || fail "%posttrans has no build loop"
[ "$purge_line" -lt "$build_loop_line" ] ||
	fail "the purge starts after the build loop (purge line $purge_line, loop line $build_loop_line): a broken stale registration makes dkms install abort first"
[ "$purge_line" -lt "$build_line" ] ||
	fail "the purge starts after dkms build (purge line $purge_line, build line $build_line)"
for body in "$postin" "$preun"; do
	printf '%s\n' "$body" | grep -F "$purge_marker" >/dev/null &&
		fail "a scriptlet other than %posttrans purges stale registrations"
done
purge_scope=$(printf '[ "$stale_name" = "%s" ]' "$name")
printf '%s\n' "$posttrans" | grep -F "$purge_scope" >/dev/null ||
	fail "%posttrans purge is not scoped to the module name $name"
purge_skip=$(printf 'if [ "$stale_version" = "%s" ]; then' "$version")
printf '%s\n' "$posttrans" | grep -F "$purge_skip" >/dev/null ||
	fail "%posttrans purge does not skip $version"
purge_remove=$(printf 'dkms remove -m %s -v "$stale_version" --all' "$name")
printf '%s\n' "$posttrans" | grep -F "$purge_remove" >/dev/null ||
	fail "%posttrans purge does not run dkms remove with --all"
# The version must come from the status line, never from a literal: a purge
# that hardcodes a version stops working at the next release.
printf '%s\n' "$posttrans" |
	grep -E '^[[:space:]]*dkms remove -m sm750hdmifb -v [^"$]' >/dev/null &&
	fail "%posttrans purge hardcodes a version instead of the status line"
# Same three properties in the spec itself, where the macros are visible.
grep -F '[ "$stale_name" = "%{dkms_name}" ]' "$spec" >/dev/null ||
	fail "spec purge is not written against %{dkms_name}"
grep -F 'if [ "$stale_version" = "%{dkms_version}" ]; then' "$spec" >/dev/null ||
	fail "spec purge is not written against %{dkms_version}"
grep -F "$purge_marker" "$spec" >/dev/null ||
	fail "spec has no stale-registration purge"

for body in "$postin" "$posttrans" "$preun"; do
	printf '%s\n' "$body" |
		grep -E '^[[:space:]]*(update-initramfs|dracut)' >/dev/null &&
		fail "scriptlet calls a Debian-only initramfs tool"
	printf '%s\n' "$body" |
		grep -E '^[[:space:]]*exit [1-9]' >/dev/null &&
		fail "scriptlet exits non-zero; that aborts the RPM transaction"
	printf '%s\n' "$body" | grep -Eq '^set -e' >/dev/null &&
		fail "scriptlet uses set -e; it must survive individual failures"
	printf '%s\n' "$body" | grep -F 'exit 0' >/dev/null ||
		fail "scriptlet does not end with exit 0"
done
# No initramfs call, but the divergence from packaging/drm-postinst is required
# to be recorded in a comment (acceptance criterion).
grep -E '^[[:space:]]*update-initramfs' "$spec" >/dev/null &&
	fail "spec calls update-initramfs"
grep -F 'update-initramfs' "$spec" >/dev/null ||
	fail "spec does not record the update-initramfs divergence"
grep -F 'drm-postinst' "$spec" >/dev/null ||
	fail "spec does not record the divergence from packaging/drm-postinst"
grep -E '^[[:space:]]*exit 1' "$spec" >/dev/null &&
	fail "spec contains an exit 1 outside a scriptlet comment"
# The supported-kernel floor must match dkms.conf and the Debian script.
pattern='6.1[7-9].*|6.[2-9][0-9].*|[7-9].*|[1-9][0-9].*) ;;'
grep -F "$pattern" "$spec" >/dev/null ||
	fail "spec kernel floor pattern drifted"
grep -F "$pattern" "$project_dir/packaging/drm-postinst" >/dev/null ||
	fail "spec kernel floor pattern does not match packaging/drm-postinst"
grep -F 'BUILD_EXCLUSIVE_KERNEL="^(6\\.(1[7-9]|[2-9][0-9])\\.|[7-9]\\.|[1-9][0-9]\\.)"' \
	"$project_dir/dkms.conf" >/dev/null ||
	fail "dkms.conf BUILD_EXCLUSIVE_KERNEL floor changed"
{
	log_header "rpm -qp --scripts $rpm_file"
	rpm -qp --scripts "$rpm_file"
} >"$evidence/02-rpm-qp-scripts.log" 2>&1
note "scriptlets: add in %post, build+install+depmod in %posttrans, remove in %preun, no %postun"

# --- %files -----------------------------------------------------------------
expected_doc=/usr/share/doc/$name
expected_usrsrc=/usr/src/$name-$version
cat >"$work/expected-files.txt" <<EOF
/etc/modprobe.d/$module.conf
/etc/modules-load.d/$module.conf
/usr/lib/$name/write-xorg-config
/usr/share/X11/xorg.conf.d/20-$module.conf
$expected_doc/LICENSE
$expected_doc/README.md
$expected_doc/RELEASE-NOTES.md
$expected_doc/TESTING.md
$expected_doc/copyright
$expected_usrsrc/LICENSE
$expected_usrsrc/Makefile
$expected_usrsrc/README.md
$expected_usrsrc/dkms.conf
$expected_usrsrc/src/Kconfig
$expected_usrsrc/src/Makefile
$expected_usrsrc/src/ddk750.h
$expected_usrsrc/src/ddk750_chip.c
$expected_usrsrc/src/ddk750_chip.h
$expected_usrsrc/src/ddk750_display.c
$expected_usrsrc/src/ddk750_display.h
$expected_usrsrc/src/ddk750_hwi2c.c
$expected_usrsrc/src/ddk750_hwi2c.h
$expected_usrsrc/src/ddk750_mode.c
$expected_usrsrc/src/ddk750_mode.h
$expected_usrsrc/src/ddk750_power.c
$expected_usrsrc/src/ddk750_power.h
$expected_usrsrc/src/ddk750_reg.h
$expected_usrsrc/src/ddk750_swi2c.c
$expected_usrsrc/src/ddk750_swi2c.h
$expected_usrsrc/src/sii902x.c
$expected_usrsrc/src/sii902x.h
$expected_usrsrc/src/sm750_dither.c
$expected_usrsrc/src/sm750_dither.h
$expected_usrsrc/src/sm750_drm.c
$expected_usrsrc/src/sm750_drm_mode.c
$expected_usrsrc/src/sm750_drm_mode.h
EOF
sort -o "$work/expected-files.txt" "$work/expected-files.txt"
rpm -qp --qf '[%{FILENAMES}\t%{FILEMODES:perms}\n]' "$rpm_file" \
	>"$work/filemodes.txt"
awk -F '\t' '$2 !~ /^d/ { print $1 }' "$work/filemodes.txt" |
	sort >"$work/actual-files.txt"
diff -u "$work/expected-files.txt" "$work/actual-files.txt" ||
	fail "%files does not match the ship list"
[ "$(wc -l <"$work/actual-files.txt")" -eq 36 ] ||
	fail "expected 36 shipped files"

cat >"$work/expected-dirs.txt" <<EOF
/usr/lib/$name
$expected_doc
$expected_usrsrc
$expected_usrsrc/src
EOF
sort -o "$work/expected-dirs.txt" "$work/expected-dirs.txt"
awk -F '\t' '$2 ~ /^d/ { print $1 }' "$work/filemodes.txt" |
	sort >"$work/actual-dirs.txt"
diff -u "$work/expected-dirs.txt" "$work/actual-dirs.txt" ||
	fail "unexpected directory entries in %files"

rpm -qplv "$rpm_file" | grep -F "/usr/lib/$name/write-xorg-config" |
	grep -q '^-rwxr-xr-x' ||
	fail "write-xorg-config is not 0755"
printf '/etc/modprobe.d/%s.conf\n/etc/modules-load.d/%s.conf\n' \
	"$module" "$module" | sort >"$work/expected-conffiles.txt"
rpm -qpc "$rpm_file" | sort >"$work/actual-conffiles.txt"
diff -u "$work/expected-conffiles.txt" "$work/actual-conffiles.txt" ||
	fail "%config file set differs from DEBIAN/conffiles"
{
	log_header "rpm -qlp / -qplv / -qpc $rpm_file"
	rpm -qlp "$rpm_file"
	printf '%s\n' '--- mode-qualified listing ---'
	rpm -qp --qf '[%{FILENAMES}\t%{FILEMODES:perms}\n]' "$rpm_file"
	printf '%s\n' '--- directories ---'
	cat "$work/actual-dirs.txt"
	printf '%s\n' '--- verbose ---'
	rpm -qplv "$rpm_file"
	printf '%s\n' '--- config files ---'
	rpm -qpc "$rpm_file"
	printf '%s\n' '--- expected ship list (docs/PACKAGING-RPM.md) ---'
	cat "$work/expected-files.txt"
} >"$evidence/03-rpm-qlp.log" 2>&1
note "%files: 36 files, 4 owned directories, 2 %config(noreplace) entries"

# --- missing-headers behaviour, rootless ------------------------------------
# The %posttrans body is extracted from the built RPM and run against synthetic
# module roots with dkms/depmod shims, so the "no supported kernel has headers"
# branch is exercised without writing to /lib/modules.
sandbox=$work/posttrans
mkdir -p "$sandbox/bin" "$sandbox/modules-none/5.15.0-generic" \
	"$sandbox/modules-none/6.18.13-200.fc43.x86_64" \
	"$sandbox/modules-mixed/5.15.0-generic" \
	"$sandbox/modules-mixed/6.18.13-200.fc43.x86_64" \
	"$sandbox/modules-mixed/7.3.4-100.fc43.x86_64/build"
: >"$sandbox/modules-mixed/7.3.4-100.fc43.x86_64/build/Makefile"
printf '%s\n' "$posttrans" >"$sandbox/posttrans.sh"
for tool in dkms depmod; do
	cat >"$sandbox/bin/$tool" <<'SHIM'
#!/bin/sh
printf '%s %s\n' "${0##*/}" "$*" >>"${SHIM_LOG:?}"
if [ "${0##*/}" = dkms ] && [ "$1" = status ]; then
	[ -n "${SHIM_STATUS:-}" ] && [ -r "$SHIM_STATUS" ] && cat "$SHIM_STATUS"
	exit 0
fi
# SHIM_FAIL_REMOVE=<version> makes "dkms remove ... -v <version> --all" fail
# the way dkms 3.4.4 fails on a broken registration: the source symlink under
# /var/lib/dkms/<name>/<version>/ dangles, so dkms.conf cannot be located and
# dkms exits 4. Empty (the default) leaves every other run unchanged.
if [ "${0##*/}" = dkms ] && [ "$1" = remove ] &&
	[ -n "${SHIM_FAIL_REMOVE:-}" ]; then
	shim_version= shim_all=0
	shift
	while [ "$#" -gt 0 ]; do
		case "$1" in
		-v) shim_version=${2:-} ;;
		--all) shim_all=1 ;;
		esac
		shift
	done
	if [ "$shim_all" -eq 1 ] && [ "$shim_version" = "$SHIM_FAIL_REMOVE" ]; then
		echo "Error! Could not locate dkms.conf file." >&2
		echo "File: /var/lib/dkms/sm750hdmifb/$shim_version/source/dkms.conf does not exist." >&2
		exit 4
	fi
fi
exit 0
SHIM
	chmod 0755 "$sandbox/bin/$tool"
done

# SHIM_STATUS lets one run hand the purged scriptlet a canned "dkms status"
# listing; it is empty for the header-branch runs below, so those see no
# registrations at all. SHIM_FAIL_REMOVE names one version whose removal must
# fail; empty means every removal succeeds.
shim_status=
shim_fail_remove=
# Arguments: 1 modules root, 2 dkms root, 3 scriptlet. The dkms root is always
# a sandbox path: the broken-tree escalation deletes directories and must never
# reach the host /var/lib/dkms.
run_posttrans() {
	SHIM_LOG=$sandbox/calls.log \
		SHIM_STATUS=$shim_status \
		SHIM_FAIL_REMOVE=$shim_fail_remove \
		SM750_RPM_MODULES_ROOT=$1 \
		SM750_RPM_DKMS_ROOT=${2:-$sandbox/dkmsroot} \
		PATH="$sandbox/bin:$PATH" \
		sh "${3:-$sandbox/posttrans.sh}"
}

: >"$sandbox/calls.log"
none_exit=0
none_output=$(run_posttrans "$sandbox/modules-none" 2>&1) || none_exit=$?
[ "$none_exit" -eq 0 ] ||
	fail "%posttrans exited $none_exit without headers; it must exit 0"
printf '%s\n' "$none_output" |
	grep -F 'no kernel received the module' >/dev/null ||
	fail "%posttrans did not warn when no kernel received the module"
printf '%s\n' "$none_output" |
	grep -F 'skipping 6.18.13-200.fc43.x86_64' >/dev/null ||
	fail "%posttrans did not warn about the header-less 6.18 kernel"
printf '%s\n' "$none_output" | grep -F '5.15.0-generic' >/dev/null &&
	fail "%posttrans considered an unsupported 5.15 kernel"
[ "$(cat "$sandbox/calls.log")" = 'dkms status' ] ||
	fail "%posttrans built or installed without a usable kernel: $(tr '\n' '|' <"$sandbox/calls.log")"

: >"$sandbox/calls.log"
mixed_exit=0
mixed_output=$(run_posttrans "$sandbox/modules-mixed" 2>&1) || mixed_exit=$?
[ "$mixed_exit" -eq 0 ] || fail "%posttrans exited $mixed_exit on the mixed root"
printf '%s\n' "$mixed_output" | grep -F 'no kernel received the module' >/dev/null &&
	fail "%posttrans warned despite one usable kernel"
# The purge is first on purpose (A37): it sees the canned listing (empty here)
# before the build loop runs.
expected_calls=$'dkms status\ndkms build -m sm750hdmifb -v 0.6.2 -k 7.3.4-100.fc43.x86_64\ndkms install -m sm750hdmifb -v 0.6.2 -k 7.3.4-100.fc43.x86_64 --force\ndepmod -a 7.3.4-100.fc43.x86_64'
[ "$(cat "$sandbox/calls.log")" = "$expected_calls" ] ||
	fail "unexpected dkms/depmod call sequence: $(tr '\n' '|' <"$sandbox/calls.log")"
mixed_calls=$(cat "$sandbox/calls.log")

# Stale-registration purge, rootless: the canned listing is the host state
# before this task (two 0.5.9 kernels, 0.6.0 installed, 0.6.2 added by %post,
# plus rows that must not be touched). Dropping the purge from %posttrans
# leaves calls.log at "dkms status" and fails the equality below.
cat >"$sandbox/status-stale.txt" <<'EOF'
sm750hdmifb/0.5.9, 7.3.3-100.fc43.x86_64, x86_64: built
sm750hdmifb/0.5.9, 7.3.4-100.fc43.x86_64, x86_64: built
sm750hdmifb/0.6.0, 7.2.15-100.fc43.x86_64, x86_64: installed
sm750hdmifb/0.6.0, 7.3.3-100.fc43.x86_64, x86_64: installed
sm750hdmifb/0.6.0: added
sm750hdmifb/0.6.2, 7.3.4-100.fc43.x86_64, x86_64: installed
sm750hdmifb/0.6.2: added
sm750hdmifb-ng/0.9.0, 7.3.4-100.fc43.x86_64, x86_64: built
othermodule/1.0, 7.3.4-100.fc43.x86_64, x86_64: installed
EOF
: >"$sandbox/calls.log"
shim_status=$sandbox/status-stale.txt
purge_exit=0
purge_output=$(run_posttrans "$sandbox/modules-none" 2>&1) || purge_exit=$?
shim_status=
[ "$purge_exit" -eq 0 ] ||
	fail "the stale-registration purge exited $purge_exit; it must tolerate failure"
printf '%s\n' "$purge_output" |
	grep -F 'removing stale DKMS registration: sm750hdmifb/0.5.9' >/dev/null ||
	fail "the purge did not announce the removal of 0.5.9"
printf '%s\n' "$purge_output" |
	grep -F 'removing stale DKMS registration: sm750hdmifb/0.6.0' >/dev/null ||
	fail "the purge did not announce the removal of 0.6.0"
printf '%s\n' "$purge_output" |
	grep -F 'removing stale DKMS registration: sm750hdmifb/0.6.2' >/dev/null &&
	fail "the purge tried to remove the version being installed"
expected_purge=$'dkms status\ndkms remove -m sm750hdmifb -v 0.5.9 --all\ndkms remove -m sm750hdmifb -v 0.6.0 --all'
[ "$(cat "$sandbox/calls.log")" = "$expected_purge" ] ||
	fail "the purge removed the wrong registrations: $(tr '\n' '|' <"$sandbox/calls.log")"
purge_calls=$(cat "$sandbox/calls.log")

# Failed-removal branch, rootless: the same canned listing, but the FIRST
# version the loop meets (0.5.9) fails to unregister the way a broken
# registration does (dangling source symlink, dkms exit 4). The load-bearing
# property is that the scriptlet still exits 0 - a non-zero exit aborts the
# whole RPM transaction - and that the failure does not abort the loop, so
# 0.6.0 is still removed afterwards.
: >"$sandbox/calls.log"
shim_status=$sandbox/status-stale.txt
shim_fail_remove=0.5.9
failpurge_exit=0
failpurge_output=$(run_posttrans "$sandbox/modules-none" 2>&1) || failpurge_exit=$?
shim_status=
shim_fail_remove=
[ "$failpurge_exit" -eq 0 ] ||
	fail "a failed stale removal exited $failpurge_exit; it must stay 0 or the transaction aborts"
printf '%s\n' "$failpurge_output" |
	grep -F 'Error! Could not locate dkms.conf file.' >/dev/null ||
	fail "the failing-removal run did not surface the shim dkms error"
printf '%s\n' "$failpurge_output" |
	grep -F 'warning: dkms remove sm750hdmifb/0.5.9 failed; remove it by hand' >/dev/null ||
	fail "the failed removal did not emit the spec warning text"
# Ordering: 0.5.9 fails first, so a later 0.6.0 removal proves the loop
# continued past the failure instead of aborting on it.
fail_line=$(grep -nF 'dkms remove -m sm750hdmifb -v 0.5.9 --all' \
	"$sandbox/calls.log" | cut -d: -f1)
cont_line=$(grep -nF 'dkms remove -m sm750hdmifb -v 0.6.0 --all' \
	"$sandbox/calls.log" | cut -d: -f1)
[ -n "$fail_line" ] || fail "the failing-removal run never attempted 0.5.9"
[ -n "$cont_line" ] ||
	fail "the loop aborted after the failed removal; 0.6.0 was never attempted"
[ "$cont_line" -gt "$fail_line" ] ||
	fail "the loop removed 0.6.0 before the failed 0.5.9 removal"
grep -F 'dkms remove -m sm750hdmifb -v 0.6.2' "$sandbox/calls.log" >/dev/null &&
	fail "the failing-removal run tried to remove the version being installed"
expected_failpurge=$'dkms status\ndkms remove -m sm750hdmifb -v 0.5.9 --all\ndkms remove -m sm750hdmifb -v 0.6.0 --all'
[ "$(cat "$sandbox/calls.log")" = "$expected_failpurge" ] ||
	fail "the failing-removal run built or installed: $(tr '\n' '|' <"$sandbox/calls.log")"
failpurge_calls=$(cat "$sandbox/calls.log")
# --- A37: a broken registration tree must not block the install -------------
# Host state after the 0.6.2-1 upgrade: /var/lib/dkms/sm750hdmifb/0.6.1 is
# still registered for the running kernel, its source/ symlink dangles because
# rpm erased the 0.6.1 package files, so "dkms install 0.6.2" aborts while
# uninstalling 0.6.1 and /lib/modules keeps the 0.6.1 module. The purge must
# delete the tree, and the install must still be attempted.
broken_scenario() { # posttrans script, scenario root; 0 when every property held
	local script=$1 root=$2 rc=0 out remove_line install_line
	rm -rf -- "$root"
	mkdir -p "$root/modules/7.3.4-100.fc43.x86_64/build" \
		"$root/dkmsroot/sm750hdmifb/0.6.1" \
		"$root/dkmsroot/othermodule/1.0"
	: >"$root/modules/7.3.4-100.fc43.x86_64/build/Makefile"
	: >"$root/dkmsroot/othermodule/1.0/canary"
	cat >"$root/status.txt" <<'EOF'
sm750hdmifb/0.6.1, 7.3.4-100.fc43.x86_64, x86_64: installed
sm750hdmifb/0.6.1: added
othermodule/1.0, 7.3.4-100.fc43.x86_64, x86_64: installed
EOF
	out=$(SHIM_LOG=$root/calls.log SHIM_STATUS=$root/status.txt \
		SHIM_FAIL_REMOVE=0.6.1 \
		SM750_RPM_MODULES_ROOT=$root/modules \
		SM750_RPM_DKMS_ROOT=$root/dkmsroot \
		PATH="$sandbox/bin:$PATH" sh "$script" 2>&1) || rc=$?
	printf '%s\n' "$out" >"$root/transcript.txt"
	[ "$rc" -eq 0 ] || { echo "exit $rc"; return 1; }
	printf '%s\n' "$out" |
		grep -F "warning: removing broken DKMS registration tree: $root/dkmsroot/sm750hdmifb/0.6.1" >/dev/null ||
		{ echo "no broken-tree warning"; return 1; }
	[ ! -e "$root/dkmsroot/sm750hdmifb/0.6.1" ] ||
		{ echo "the broken tree survived"; return 1; }
	[ -e "$root/dkmsroot/othermodule/1.0/canary" ] ||
		{ echo "the purge deleted another module's tree"; return 1; }
	printf '%s\n' "$out" | grep -F 'dkms install failed' >/dev/null &&
		{ echo "dkms install failed"; return 1; }
	grep -F 'dkms install -m sm750hdmifb -v 0.6.2 -k 7.3.4-100.fc43.x86_64 --force' \
		"$root/calls.log" >/dev/null ||
		{ echo "dkms install was not attempted"; return 1; }
	remove_line=$(grep -nF 'dkms remove -m sm750hdmifb -v 0.6.1 --all' \
		"$root/calls.log" | cut -d: -f1)
	install_line=$(grep -nF 'dkms install -m sm750hdmifb -v 0.6.2' \
		"$root/calls.log" | cut -d: -f1)
	[ -n "$remove_line" ] && [ -n "$install_line" ] &&
		[ "$remove_line" -lt "$install_line" ] ||
		{ echo "the install did not follow the purge"; return 1; }
	return 0
}
broken_scenario "$sandbox/posttrans.sh" "$sandbox/broken" ||
	fail "the broken 0.6.1 registration was not cleared before the install: $(cat "$sandbox/broken/transcript.txt" 2>/dev/null)"
broken_transcript=$(cat "$sandbox/broken/transcript.txt")
broken_calls=$(cat "$sandbox/broken/calls.log")

# --- A37: a status field that is not a release token must not reach a path --
# "dkms status" is a text listing. A version field of ".." would resolve
# <dkms_root>/sm750hdmifb/.. to the dkms root itself, and the broken-tree
# escalation would then delete the whole root.
unsafe_scenario() { # posttrans script, scenario root
	local script=$1 root=$2 rc=0 out
	rm -rf -- "$root"
	mkdir -p "$root/modules" "$root/dkmsroot/sm750hdmifb/0.6.0"
	: >"$root/dkmsroot/canary"
	: >"$root/dkmsroot/sm750hdmifb/0.6.0/canary"
	cat >"$root/status.txt" <<'EOF'
sm750hdmifb/../etc, 6.17.0-1.fc43.x86_64, x86_64: installed
sm750hdmifb/.., 6.17.0-1.fc43.x86_64, x86_64: installed
sm750hdmifb/., 6.17.0-1.fc43.x86_64, x86_64: installed
sm750hdmifb/0.6.1~x, 6.17.0-1.fc43.x86_64, x86_64: installed
EOF
	out=$(SHIM_LOG=$root/calls.log SHIM_STATUS=$root/status.txt \
		SHIM_FAIL_REMOVE=.. \
		SM750_RPM_MODULES_ROOT=$root/modules \
		SM750_RPM_DKMS_ROOT=$root/dkmsroot \
		PATH="$sandbox/bin:$PATH" sh "$script" 2>&1) || rc=$?
	printf '%s\n' "$out" >"$root/transcript.txt"
	[ "$rc" -eq 0 ] || { echo "exit $rc"; return 1; }
	[ -e "$root/dkmsroot/canary" ] ||
		{ echo "a path outside the version tree was removed"; return 1; }
	[ -e "$root/dkmsroot/sm750hdmifb/0.6.0/canary" ] ||
		{ echo "the dkms root was wiped"; return 1; }
	grep -E 'dkms remove .* -v (\.\.|\.|\.\./etc|0\.6\.1~x) ' "$root/calls.log" >/dev/null &&
		{ echo "an unsafe version reached dkms remove"; return 1; }
	return 0
}
unsafe_scenario "$sandbox/posttrans.sh" "$sandbox/unsafe" ||
	fail "a crafted dkms status version reached a path: $(cat "$sandbox/unsafe/transcript.txt" 2>/dev/null)"
unsafe_transcript=$(cat "$sandbox/unsafe/transcript.txt")
unsafe_calls=$(cat "$sandbox/unsafe/calls.log")

# --- A38/A39: dead dkms directive, unconditional console hint --------------
# dkms 3.4.4 reads CLEAN only to print "Deprecated feature: CLEAN"
# (/usr/sbin/dkms:582-585 is the sole occurrence in the whole script); the
# directive is never executed, so its return must fail this gate.
no_deprecated_directive() { # dkms.conf
	grep -Eq '^[[:space:]]*CLEAN[[:space:]]*=' "$1" && return 1
	return 0
}
no_deprecated_directive "$project_dir/dkms.conf" ||
	fail "dkms.conf carries CLEAN again; dkms 3.4.4 only warns that it is deprecated"

# tools/sm750-console.sh printed "(crc32 0xe20eea22 is 262144 zero bytes:
# nothing has painted the window)" for every frame, including the observed test
# card (crc32 0x3972ef44). The hint must sit inside the zero-frame branch.
hint_is_conditional() { # helper
	local guard hint other
	guard=$(grep -nF 'if [ "$crc" = "0xe20eea22" ]; then' "$1" |
		head -n 1 | cut -d: -f1)
	hint=$(grep -nF 'nothing has painted the window' "$1" |
		head -n 1 | cut -d: -f1)
	other=$(grep -nF 'this frame is not it' "$1" | head -n 1 | cut -d: -f1)
	[ -n "$guard" ] && [ -n "$hint" ] && [ -n "$other" ] &&
		[ "$hint" -eq $((guard + 1)) ] &&
		[ "$other" -gt "$hint" ] && [ "$other" -le $((hint + 3)) ]
}
purge_before_build() { # posttrans script
	local purge loop
	purge=$(grep -nF "$purge_marker" "$1" | head -n 1 | cut -d: -f1)
	loop=$(grep -nE '^[[:space:]]*for kernel_dir in ' "$1" |
		head -n 1 | cut -d: -f1)
	[ -n "$purge" ] && [ -n "$loop" ] && [ "$purge" -lt "$loop" ]
}
helper=$project_dir/tools/sm750-console.sh
hint_is_conditional "$helper" ||
	fail "the console helper prints the zero-frame hint outside the zero-frame branch"
purge_before_build "$sandbox/posttrans.sh" ||
	fail "the extracted %posttrans runs the build loop before the purge"

# Planted defects: the check above each plant must reject it.
plant_dir=$sandbox/plant
mkdir -p "$plant_dir"
controls=0
control_lines=
plant() { # name, source file, mutation function, detector function
	local name=$1 planted=$plant_dir/plant_$1
	cp "$2" "$planted"
	"$3" "$planted"
	if "$4" "$planted"; then
		fail "planted control $name was not rejected"
	fi
	controls=$((controls + 1))
	control_lines="$control_lines plant_$name"
	printf 'plant_%s: rejected\n' "$name"
}
plant_functional() { # name, scriptlet, mutation function, scenario function
	local name=$1 planted=$plant_dir/plant_$1.sh
	local out=$plant_dir/plant_$1.log
	cp "$2" "$planted"
	"$3" "$planted"
	if "$4" "$planted" "$plant_dir/plant_$1" >"$out" 2>&1; then
		fail "planted control $name was not rejected"
	fi
	controls=$((controls + 1))
	control_lines="$control_lines plant_$name"
	printf 'plant_%s: rejected (%s)\n' "$name" "$(head -n 1 "$out")"
}
plant_purge_after_build() {
	awk '/^seen_versions=/ && !done {
		print "for kernel_dir in \"$modules_root\"/*; do :; done"
		done = 1
	} { print }' "$1" >"$1.planted" && mv "$1.planted" "$1"
}
plant_no_tree_escalation() {
	awk '/^\tif \[ -d "\$stale_tree" \] &&/ { skip = 1 }
		skip && /^\tfi$/ { skip = 0; next }
		!skip' "$1" >"$1.planted"
	mv "$1.planted" "$1"
}
plant_unsafe_version() {
	grep -vF -e '*/*|.|..) continue ;;' \
		-e '*[!0-9A-Za-z._-]*) continue ;;' "$1" >"$1.planted"
	mv "$1.planted" "$1"
}
plant_clean_directive() {
	printf 'CLEAN="make KDIR=${kernel_source_dir} clean"\n' >>"$1"
}
plant_unconditional_hint() {
	awk '/if \[ "\$crc" = "0xe20eea22" \]; then/ && !done {
		print "\t\tsay \"(crc32 0xe20eea22 is 262144 zero bytes: nothing has painted the window)\""
		done = 1
	} { print }' "$1" >"$1.planted" && mv "$1.planted" "$1"
}
plant purge_after_build "$sandbox/posttrans.sh" \
	plant_purge_after_build purge_before_build
plant clean_directive "$project_dir/dkms.conf" \
	plant_clean_directive no_deprecated_directive
plant unconditional_hint "$helper" \
	plant_unconditional_hint hint_is_conditional
plant_functional broken_tree_escalation "$sandbox/posttrans.sh" \
	plant_no_tree_escalation broken_scenario
plant_functional unsafe_version "$sandbox/posttrans.sh" \
	plant_unsafe_version unsafe_scenario

{
	log_header "sh posttrans.sh with SM750_RPM_MODULES_ROOT (rootless)"
	printf '%s\n' '--- no supported kernel with headers ---'
	printf '%s\n' "$none_output"
	printf 'exit: %s\n' "$none_exit"
	printf '%s\n' '--- one usable kernel, one header-less kernel ---'
	printf '%s\n' "$mixed_output"
	printf 'exit: %s\n' "$mixed_exit"
	printf '%s\n' '--- recorded calls (mixed root) ---'
	printf '%s\n' "$mixed_calls"
	printf '%s\n' '--- stale registrations handed to the purge ---'
	cat "$sandbox/status-stale.txt"
	printf '%s\n' '--- purge run (no usable kernel, canned status) ---'
	printf '%s\n' "$purge_output"
	printf 'exit: %s\n' "$purge_exit"
	printf '%s\n' '--- recorded calls (purge run) ---'
	printf '%s\n' "$purge_calls"
	printf '%s\n' '--- purge run with a FAILED removal (SHIM_FAIL_REMOVE=0.5.9) ---'
	printf '%s\n' 'command: SHIM_FAIL_REMOVE=0.5.9 SHIM_STATUS=status-stale.txt sh posttrans.sh'
	printf '%s\n' 'purpose: dkms 3.4.4 exits 4 for a broken registration (dangling'
	printf '%s\n' 'source symlink); the scriptlet must warn, keep exit 0 and keep'
	printf '%s\n' 'purging the remaining stale versions.'
	printf '%s\n' "$failpurge_output"
	printf 'exit: %s\n' "$failpurge_exit"
	printf '%s\n' '--- recorded calls (failed-removal run) ---'
	printf '%s\n' "$failpurge_calls"
	printf '%s\n' '--- purge before the build loop (A37), line numbers from posttrans.sh ---'
	printf 'purge line: %s, build loop line: %s\n' "$purge_line" "$build_loop_line"
	printf '%s\n' '--- broken 0.6.1 registration (A37), dkms root in the sandbox ---'
	printf '%s\n' 'state: /var/lib/dkms/sm750hdmifb/0.6.1 registered for the running'
	printf '%s\n' 'kernel with no source/dkms.conf, so dkms install 0.6.2 aborts while'
	printf '%s\n' 'uninstalling 0.6.1 (SHIM_FAIL_REMOVE=0.6.1). The purge must delete'
	printf '%s\n' 'the tree and the install must still be attempted.'
	printf '%s\n' "$broken_transcript"
	printf '%s\n' '--- recorded calls (broken-tree run) ---'
	printf '%s\n' "$broken_calls"
	printf '%s\n' '--- status fields that are not release tokens (A37) ---'
	cat "$sandbox/unsafe/status.txt"
	printf '%s\n' "$unsafe_transcript"
	printf '%s\n' '--- recorded calls (unsafe-version run) ---'
	printf '%s\n' "$unsafe_calls"
	printf '%s\n' '--- planted defects (each must be rejected) ---'
	printf 'rejected:%s\ntotal: %s\n' "$control_lines" "$controls"
} >"$evidence/06-posttrans-missing-headers.log" 2>&1
note "missing headers: warning on stderr, exit 0; purge, build, install, depmod sequence verified"
note "stale purge: sm750hdmifb/0.5.9 and 0.6.0 removed, 0.6.2 and other module names untouched"
note "failed removal: dkms exit 4 downgraded to the spec warning, exit 0, loop continued"
note "broken 0.6.1 tree: deleted before the build loop, install still attempted, exit 0"
note "unsafe status field: skipped before any path is formed, dkms root intact"
note "dkms.conf has no CLEAN directive; console zero-frame hint is conditional"
note "planted controls: $controls rejected"

# --- dkms sandbox: add + build ---------------------------------------------
# The source comes from the built RPM payload, so this also proves the packaged
# tree is a complete dkms source.
mkdir -p "$work/payload" "$dkms_root/src" "$dkms_root/install" "$dkms_root/build"
rpm2cpio "$rpm_file" | (cd "$work/payload" && cpio -idm --quiet)
payload_src=$work/payload/usr/src/$name-$version
[ -f "$payload_src/dkms.conf" ] || fail "payload has no dkms.conf"
no_deprecated_directive "$payload_src/dkms.conf" ||
	fail "the packaged dkms.conf carries the dead CLEAN directive"
cp -a "$payload_src" "$dkms_root/src/$name-$version"
dkms_base=(dkms --dkmstree "$dkms_root" --sourcetree "$dkms_root/src"
	--installtree "$dkms_root/install" -m "$name" -v "$version")
export CC=$cc

# Kernel-header lookup inside the sandbox. With a custom --installtree, dkms
# resolves the kernel tree at <installtree>/<kver>/build or <installtree>/
# <kver>/source, so a bare sandbox reports "kernel headers cannot be found"
# even though this host has them. Point the sandbox at the real tree with a
# symlink (read-only, scratch-side only); --kernelsourcedir is the fallback.
header_tree=/usr/src/kernels/$kernel
install_kernel_dir=$dkms_root/install/$kernel
mkdir -p "$install_kernel_dir"
build_extra=()
if [ -d "$header_tree" ]; then
	ln -sfn "$header_tree" "$install_kernel_dir/build"
else
	build_extra=("--kernelsourcedir=$(readlink -f "/lib/modules/$kernel/build")")
fi
{
	log_header "host headers for $kernel"
	printf 'link /lib/modules/%s/build -> %s\n' "$kernel" \
		"$(readlink -f "/lib/modules/$kernel/build")"
	printf 'kernel source tree: %s\n' "$header_tree"
	printf 'sandbox header link: %s\n' "$install_kernel_dir/build"
	printf 'note: the header tree is present on this host; an earlier failure of\n'
	printf 'this script was an installtree-relative lookup artifact, not a\n'
	printf 'missing kernel-devel package.\n'
} >"$evidence/05-dkms-sandbox.log" 2>&1
{
	log_header "${dkms_base[*]} add (running kernel $kernel)"
	"${dkms_base[@]}" add
} >>"$evidence/05-dkms-sandbox.log" 2>&1 || {
	tail -n 40 "$evidence/05-dkms-sandbox.log" >&2
	fail "dkms sandbox add failed (see $evidence/05-dkms-sandbox.log)"
}
{
	# Fallback path only (see the header-link block above).
	printf '\n--- %s build -k %s %s ---\n' "${dkms_base[*]}" "$kernel" \
		"${build_extra[*]}"
	"${dkms_base[@]}" build -k "$kernel" ${build_extra[@]+"${build_extra[@]}"}
} >>"$evidence/05-dkms-sandbox.log" 2>&1 || {
	tail -n 40 "$evidence/05-dkms-sandbox.log" >&2
	fail "dkms sandbox build failed (see $evidence/05-dkms-sandbox.log)"
}
# dkms 3.4.4 refuses "install" for a non-root caller even when every tree is a
# scratch path, so the sandbox stops at "built". The refusal is captured as
# evidence instead of being skipped silently.
install_rc=0
{
	printf '\n--- %s install -k %s --force --no-depmod (refusal expected) ---\n' \
		"${dkms_base[*]}" "$kernel"
	"${dkms_base[@]}" install -k "$kernel" --force --no-depmod
} >>"$evidence/05-dkms-sandbox.log" 2>&1 || install_rc=$?
[ "$install_rc" -ne 0 ] ||
	fail "dkms sandbox install succeeded; it must stay a root-only step"
grep -F 'You must be root' "$evidence/05-dkms-sandbox.log" >/dev/null ||
	fail "dkms install did not report the expected non-root refusal"
dkms_status=$("${dkms_base[@]}" status 2>&1) ||
	fail "dkms status failed: $dkms_status"
{
	printf '\n--- %s status ---\n' "${dkms_base[*]}"
	printf '%s\n' "$dkms_status"
} >>"$evidence/05-dkms-sandbox.log" 2>&1
printf '%s\n' "$dkms_status" |
	grep -Eq "^$name/$version, $kernel, [^:]+: built$" ||
	fail "sandbox dkms status is not 'built': $dkms_status"
printf '%s\n' "$dkms_status" | grep -F 'installed' >/dev/null &&
	fail "dkms reports installed; the sandbox must never install"

# A status string alone is not proof: require the compiled object in the
# sandbox tree, and require the host module tree to be untouched.
built_ko=$(find "$dkms_root" -path "*/$module.ko" -type f | head -n 1)
[ -n "$built_ko" ] && [ -s "$built_ko" ] ||
	fail "no $module.ko under the dkms sandbox ($dkms_root)"
host_ko=/lib/modules/$kernel/updates/dkms/$module.ko
[ ! -e "$host_ko" ] ||
	fail "the sandbox run leaked a module into $host_ko; builds must stay rootless"
{
	printf '\n--- built object (sandbox tree, install is root-only) ---\n'
	ls -l "$built_ko"
	printf '%s\n' '--- host module tree (must be absent) ---'
	[ -e "$host_ko" ] && ls -l "$host_ko" || printf 'absent: %s\n' "$host_ko"
	printf '%s\n' '--- vermagic ---'
	modinfo -F vermagic "$built_ko" 2>/dev/null || true
} >>"$evidence/05-dkms-sandbox.log" 2>&1
printf '%s\n' "$(modinfo -F vermagic "$built_ko" 2>/dev/null)" |
	grep -F "$kernel" >/dev/null ||
	fail "built module vermagic does not target $kernel"
note "dkms sandbox: $dkms_status"
note "built object: $built_ko ($(stat -c %s "$built_ko") bytes, host tree untouched)"

# --- root-only steps: reported, never executed -----------------------------
skip "dnf install $(basename "$rpm_file"): needs root (writes /usr/src, /etc, /var/lib/dkms)"
skip "dkms status showing 'installed' in the host tree: needs root, follows the skipped dnf install"
skip "dkms install (even with --installtree): 'Error! You must be root to use this command.'"
skip "dkms remove -m sm750hdmifb -v 0.5.9 --all in the host tree: not in the sudoers allowlist (only -v 0.6.2 is); the purge runs inside the RPM %posttrans instead, and the rootless run above proves the call sequence"
skip "modinfo of the installed module: needs root, follows the skipped dnf install"
skip "dnf remove $name: needs root and the skipped dnf install"
skip "dkms status after erase (registration gone): needs root, follows the skipped dnf remove"
skip "closing commands recorded in docs/evidence/EVIDENCE-GAPS.md GAP-B7"

[ ! -e "$HOME/rpmbuild" ] ||
	fail "test wrote $HOME/rpmbuild; explicit _topdir was not honoured"
printf 'RPM/DKMS checks passed: %s %s, sandbox built, %s planted controls rejected, root-only steps skipped\n' \
	"$name" "$version" "$controls"
