#!/bin/bash
export PATH=/root/xc/inst/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
W=/root/xc/inst/aarch64-pc-cygwin/include/w32api
BLD=/root/xc/bld

echo "=== mbstate_t error full context (first occurrence) ==="
grep -n -B12 "wchar.h:86:20: error: conflicting declaration" /root/xc/winsup-build.log | head -30

# ---- LOCAL EXPERIMENT: teach mingw-w64 that aarch64-pc-cygwin is a 64-bit Windows target ----
cp $W/_cygwin.h $W/_cygwin.h.orig
sed -i 's|^#ifdef __x86_64__$|#if defined(__x86_64__) \|\| defined(__aarch64__)|' $W/_cygwin.h
echo "=== patched _cygwin.h ==="
sed -n '28,36p' $W/_cygwin.h

cp $W/basetsd.h $W/basetsd.h.orig
sed -i 's|^#if (defined (__x86_64__) \|\| defined (__ia64__)) \&\& !(defined (__WIDL__) \|\| defined (RC_INVOKED))$|#if (defined (__x86_64__) \|\| defined (__ia64__) \|\| defined (__aarch64__)) \&\& !(defined (__WIDL__) \|\| defined (RC_INVOKED))|' $W/basetsd.h
sed -n '10,11p' $W/basetsd.h

echo "=== re-probe sizeof(UINT_PTR) ==="
cd /root/xc/t
aarch64-pc-cygwin-gcc -c probe.c -o probe.o \
  -isystem /root/xc/runtime/winsup/cygwin/include \
  -isystem /root/xc/bld/newlib/targ-include \
  -isystem /root/xc/runtime/newlib/libc/include 2>&1 | head -5
echo "UINT_PTR_PROBE_RESULT=$? (0 lines above == UINT_PTR is 64-bit)"
