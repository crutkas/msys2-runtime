#!/bin/bash
BLD=/root/xc/bld/newlib
cd $BLD
echo "=== Makefile mtime ==="; stat -c '%y %n' Makefile
echo "=== conditional values in config.log ==="
grep -E "^(HAVE_FPMATH_H|HAVE_LIBM_MACHINE_AARCH64)_(TRUE|FALSE)=" config.log
echo "=== counts ==="
echo -n "ld/    : "; grep -c 'libm/ld/libm_a-' Makefile
echo -n "ld128/ : "; grep -c 'libm/ld128/libm_a-' Makefile
echo "=== sample lines ==="
grep -m3 'libm/ld/libm_a-e_acoshl' Makefile
echo "=== does Makefile.in conditionalize them? ==="
grep -m3 'libm/ld/libm_a-e_acoshl' Makefile.in 2>/dev/null || echo "(no Makefile.in here)"
grep -m3 'libm/ld/libm_a-e_acoshl' /root/xc/runtime/newlib/Makefile.in | head -3
