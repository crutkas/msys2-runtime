#!/bin/bash
export PATH=/root/xc/inst/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
W=/root/xc/inst/aarch64-pc-cygwin/include/w32api
echo "=== how mingw-w64 basetsd.h decides 64-bitness ==="
grep -n '_WIN64\|__x86_64__\|__aarch64__\|_M_AMD64\|_M_ARM64' $W/basetsd.h | head -30
echo
echo "=== _mingw.h __CYGWIN__ block (lines 1..40) ==="
sed -n '1,40p' $W/_mingw.h
echo
echo "=== _mingw_mac.h / _mingw.h: where _WIN64 would be set ==="
grep -rn 'define _WIN64\|defined(_WIN64)' $W/_mingw.h $W/_mingw_mac.h $W/_cygwin.h 2>/dev/null | head -20
echo
echo "=== _cygwin.h ==="
cat $W/_cygwin.h 2>/dev/null | head -60
echo
echo "=== probe: sizeof(UINT_PTR) as the build sees it ==="
cd /root/xc/t
cat > probe.c <<'EOF'
#include <w32api/windows.h>
char a[sizeof(UINT_PTR)==8 ? 1 : -1];
char b[sizeof(void*)==8 ? 1 : -1];
EOF
aarch64-pc-cygwin-gcc -c probe.c -o probe.o \
  -isystem /root/xc/runtime/winsup/cygwin/include \
  -isystem /root/xc/bld/newlib/targ-include \
  -isystem /root/xc/runtime/newlib/libc/include 2>&1 | head -10
echo "PROBE_EXIT=$?"
