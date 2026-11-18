// SPDX-License-Identifier: GPL-2.0-only
//
// Report sizeof(<pointer>) passed as the length to memcpy()/memset(): the size
// of the pointed-to type was almost certainly meant. Report-only, so the rule
// prints via a Python script rather than transforming anything.

@r_memcpy@
type T;
T *p;
expression dst, src;
position p1;
@@
 memcpy@p1(dst, src, sizeof(p))

@r_memset@
type T;
T *p;
expression dst, val;
position p1;
@@
 memset@p1(dst, val, sizeof(p))

@script:python depends on r_memcpy@
p1 << r_memcpy.p1;
@@
print("sizeof-pointer: %s:%s" % (p1[0].file, p1[0].line))

@script:python depends on r_memset@
p1 << r_memset.p1;
@@
print("sizeof-pointer: %s:%s" % (p1[0].file, p1[0].line))
