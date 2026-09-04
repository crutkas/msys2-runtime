#!/bin/bash
export PATH=/root/xc/inst/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
S=/root/xc/runtime
echo "=== newlib sys/config.h MALLOC_ALIGNMENT context (which branch does aarch64 take?) ==="
grep -n -B6 'define MALLOC_ALIGNMENT' $S/newlib/libc/include/sys/config.h
echo
echo "=== what the compiler actually sees ==="
cd /root/xc/t
printf '#include <sys/config.h>\nMALLOC_ALIGNMENT\n' > m.c
aarch64-pc-cygwin-gcc -E -P m.c -isystem $S/winsup/cygwin/include \
  -isystem /root/xc/bld/newlib/targ-include -isystem $S/newlib/libc/include 2>/dev/null | tail -2
