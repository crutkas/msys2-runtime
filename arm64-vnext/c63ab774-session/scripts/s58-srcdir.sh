#!/bin/bash
# w-autoload/bld was configured with srcdir=/root/xc/runtime (the PRESERVED, UNFIXED tree).
# Repoint the combined build dir at /root/xc/w-link/runtime, which carries BOTH fixes.
# target_builddir=/root/xc/bld is left alone: it is only READ (newlib libc.a/libm.a, cygserver).
set -u
L=/root/xc/w-link

echo "=== before ==="
grep -m2 '^srcdir = \|^abs_srcdir = ' $L/bld/winsup/cygwin/Makefile

N=$(grep -rl '/root/xc/runtime' $L/bld 2>/dev/null | wc -l)
echo "files referencing /root/xc/runtime : $N"

grep -rl '/root/xc/runtime' $L/bld 2>/dev/null \
  | while read -r f; do sed -i 's|/root/xc/runtime|/root/xc/w-link/runtime|g' "$f"; done

echo
echo "=== after ==="
grep -m2 '^srcdir = \|^abs_srcdir = ' $L/bld/winsup/cygwin/Makefile
echo "remaining /root/xc/runtime refs (want 0): $(grep -rl '/root/xc/runtime' $L/bld 2>/dev/null | grep -v w-link | wc -l)"

echo
echo "=== target_builddir must still point at the preserved (read-only) libs ==="
grep -m1 '^target_builddir = ' $L/bld/winsup/cygwin/Makefile
ls -la /root/xc/bld/newlib/libc.a /root/xc/bld/newlib/libm.a

echo
echo "=== the build now sees BOTH fixes ==="
printf 'autoload.cc balign : %s\n' "$(grep -c balign $L/runtime/winsup/cygwin/autoload.cc)"
printf 'gendef lines       : %s\n' "$(wc -l < $L/runtime/winsup/cygwin/scripts/gendef)"
printf 'tlsoffsets lines   : %s\n' "$(wc -l < $L/bld/winsup/cygwin/tlsoffsets)"

echo
echo "=== force regeneration of msys.def + sigfe.s from the FIXED gendef ==="
rm -f $L/bld/winsup/cygwin/msys.def $L/bld/winsup/cygwin/sigfe.s $L/bld/winsup/cygwin/sigfe.o
rm -f $L/bld/winsup/cygwin/autoload.o
ls -la $L/bld/winsup/cygwin/msys.def $L/bld/winsup/cygwin/sigfe.s 2>&1 | tail -2
echo "(removed; make will regenerate)"
