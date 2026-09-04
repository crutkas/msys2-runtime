#!/bin/bash
S=/root/xc/runtime/winsup/cygwin
echo "=== cygmalloc.h:1-35 ==="
sed -n '1,35p' $S/local_includes/cygmalloc.h
echo
echo "=== where else MALLOC_ALIGNMENT comes from ==="
grep -rn 'MALLOC_ALIGNMENT' /root/xc/runtime/newlib/libc/include/ /root/xc/bld/newlib/targ-include/ 2>/dev/null | head
echo
echo "=== cygwin.sc.in ==="
sed -n '1,20p' $S/cygwin.sc.in
echo
echo "=== math/fabsl.c ==="
cat $S/math/fabsl.c
echo
echo "=== Makefile.am TARGET_AARCH64 blocks in the PATCHED tree ==="
grep -n -A14 'if TARGET_AARCH64' $S/Makefile.am | head -50
echo
echo "=== total .o targets the Makefile intends to build ==="
cd /root/xc/bld/winsup/cygwin
grep -o '[a-zA-Z0-9_./-]*\.\$(OBJEXT)' Makefile | sort -u | wc -l
