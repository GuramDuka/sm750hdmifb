// SPDX-License-Identifier: GPL-2.0-only
//
// Report a pointer dereferenced in the same expression that tests it for NULL
// with the wrong operator, e.g. (p == NULL && p->f) or (p != NULL || p->f):
// no evaluation order makes that dereference guarded. Report-only.

@r@
expression E;
identifier f;
position p;
@@
(
  (E == NULL && ... && <+...E->f@p...+>)
|
  (E != NULL || ... || <+...E->f@p...+>)
)

@script:python depends on r@
p << r.p;
@@
print("deref-under-null-check: %s:%s" % (p[0].file, p[0].line))
