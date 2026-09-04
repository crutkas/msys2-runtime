#!/bin/bash
# Reconfigure newlib so that libm/ld (80/128-bit long double) and libm/ld128 are NOT built.
# Rationale: aarch64-pc-cygwin sets _LDBL_EQ_DBL=1 (long double == double, 64-bit), but
#   - libm/Makefile.inc pulls ld128/ whenever HAVE_LIBM_MACHINE_AARCH64 (correct only for ELF aarch64)
#   - HAVE_FPMATH_H is true because libc/machine/aarch64/machine/_fpmath.h exists (113-bit quad)
# Both are wrong for Windows/Cygwin ARM64. This is a NEWLIB PORT GAP, recorded as evidence.
set -e
SRC=/root/xc/runtime/newlib
BLD=/root/xc/bld/newlib
export PATH=/root/xc/inst/bin:$PATH

echo "=== original configure line ==="
CFGLINE=$(grep -m1 '^  \$ .*configure' "$BLD/config.log" | sed 's/^  \$ //')
echo "$CFGLINE"

# 1. libm_machine_dir='' for aarch64 -> drops HAVE_LIBM_MACHINE_AARCH64 -> drops ld128/
if grep -q "libm_machine_dir=aarch64" "$SRC/configure.host"; then
  sed -i "s/^\tlibm_machine_dir=aarch64$/\tlibm_machine_dir=/" "$SRC/configure.host"
  echo "patched configure.host libm_machine_dir"
fi
grep -n -A3 'aarch64\*)' "$SRC/configure.host" | head -8

# 2. hide _fpmath.h across configure only -> HAVE_FPMATH_H=false -> drops ld/
FPM="$SRC/libc/machine/aarch64/machine/_fpmath.h"
mv "$FPM" "$FPM.hidden"

cd "$BLD"
rm -f config.cache
set +e
eval "$CFGLINE" > cfg2.log 2>&1
RC=$?
set -e
mv "$FPM.hidden" "$FPM"
echo "CONFIGURE EXIT $RC"
tail -5 cfg2.log
echo "=== remaining ld objects in Makefile (want 0) ==="
grep -c 'libm/ld/libm_a-\|libm/ld128/libm_a-' Makefile
