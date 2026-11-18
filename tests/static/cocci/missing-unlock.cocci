// SPDX-License-Identifier: GPL-2.0-only
//
// Report two error-path lock leaks. Report-only, so the rules print via a
// Python script instead of transforming anything.
//
//   1. a return nested inside an if() between a lock and its unlock: the
//      unlock is skipped on that path;
//   2. a return after a lock with no unlock anywhere in between.
//
// The lock arguments must be the ellipsis form; the expression-metavariable
// form (mutex_lock(L)) matches nothing. The `if (E) return` shape has to be
// spelled out - a bare `return ...;` inside `<+... ...+>` also matches the
// correct unlock-then-return sequence and would report working code.

@leak_mutex@
position p;
identifier fn;
expression E;
@@
fn(...) {
 <+...
 mutex_lock(...);
 <+...
 if (E) return@p ...;
 ...+>
 mutex_unlock(...);
 ...+>
}

@leak_spin@
position p;
identifier fn;
expression E;
@@
fn(...) {
 <+...
 spin_lock_irqsave(...);
 <+...
 if (E) return@p ...;
 ...+>
 spin_unlock_irqrestore(...);
 ...+>
}

@leak_never_mutex@
position p;
@@
 mutex_lock(...);
 ... when != mutex_unlock(...);
 return@p ...;

@leak_never_spin@
position p;
@@
 spin_lock_irqsave(...);
 ... when != spin_unlock_irqrestore(...);
 return@p ...;

@script:python depends on leak_mutex@
p << leak_mutex.p;
@@
print("missing-unlock: %s:%s" % (p[0].file, p[0].line))

@script:python depends on leak_spin@
p << leak_spin.p;
@@
print("missing-unlock: %s:%s" % (p[0].file, p[0].line))

@script:python depends on leak_never_mutex@
p << leak_never_mutex.p;
@@
print("missing-unlock: %s:%s" % (p[0].file, p[0].line))

@script:python depends on leak_never_spin@
p << leak_never_spin.p;
@@
print("missing-unlock: %s:%s" % (p[0].file, p[0].line))
