#!/bin/bash
# Rebuild newlib against the FIXED cygwin/config.h (x18 TEB access).
# The preserved /root/xc/bld/newlib was built against the OLD header, so its
# libc.a/libm.a carry inlined __getreent copies using `mrs tpidr_el0` -- that is
# where the 289 residual sites in the linked DLL come from.
# Build a COPY under /root/xc/w-link; preserved assets are not touched.
set -u
export PATH=/root/xc/inst/bin:$PATH
L=/root/xc/w-link

echo "=== copy the preserved newlib build tree ==="
rm -rf $L/bld/newlib
cp -a /root/xc/bld/newlib $L/bld/newlib

echo "=== repoint TEXT FILES ONLY (grep -rIl; -rl would corrupt objects) ==="
T=$(grep -rIl '/root/xc/runtime' $L/bld/newlib 2>/dev/null | wc -l)
A=$(grep -rl  '/root/xc/runtime' $L/bld/newlib 2>/dev/null | wc -l)
echo "text=$T  all(incl binary)=$A"
grep -rIl '/root/xc/runtime' $L/bld/newlib 2>/dev/null \
  | while read -r f; do sed -i 's|/root/xc/runtime|/root/xc/w-link/runtime|g' "$f"; done
grep -m2 '^srcdir = \|^abs_srcdir = ' $L/bld/newlib/Makefile

echo
echo "=== confirm the fixed header is the one on the include path ==="
grep -c 'mov %0, x18' $L/runtime/winsup/cygwin/include/cygwin/config.h
grep -c 'tpidr_el0' $L/runtime/winsup/cygwin/include/cygwin/config.h

echo
echo "=== full rebuild of newlib ==="
cd $L/bld/newlib || exit 1
find . -name '*.o' -delete
rm -f libc.a libm.a libg.a
timeout 2400 make -j12 > /root/xc/newlib-teb.log 2>&1
echo "MAKE EXIT $?"
grep -c 'error:' /root/xc/newlib-teb.log
ls -la libc.a libm.a 2>&1

echo
echo "=== tpidr_el0 remaining in the new libc.a? ==="
printf 'libc.a : %s\n' "$(aarch64-pc-cygwin-objdump -d libc.a 2>/dev/null | grep -c tpidr_el0)"
printf 'libm.a : %s\n' "$(aarch64-pc-cygwin-objdump -d libm.a 2>/dev/null | grep -c tpidr_el0)"
