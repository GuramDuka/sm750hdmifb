# SPDX-License-Identifier: GPL-2.0-only
#
# The one definition of development-only material: kept in git, never shipped
# in the source archive. build-package.sh builds the archive from this list,
# tests/audit-release.sh forbids the same paths inside it, and
# tests/check-rpm-dkms.sh rebuilds the same archive for the DKMS payload, so a
# new development directory is added here once and every consumer follows
# (defect A29: the packager and the release audit each carried their own copy
# of the rule and drifted apart).
#
# Entries are directories relative to the repository root; each is excluded
# with its whole subtree.

sm750_dev_only=(
	docs/plan
	docs/evidence
	docs/images
	# Research notes quote vendor documents whose redistribution terms are
	# unknown, so they are tracked but never shipped.
	docs/notes
)

# The git pathspecs that drop every entry above, one per line, for
# `git ls-files -- . $(...)`. The bare directory pathspec covers the whole
# subtree, so callers never need a trailing /*.
sm750_dev_only_pathspecs() {
	local path
	for path in "${sm750_dev_only[@]}"; do
		printf '%s\n' ":(exclude)${path}"
	done
}
