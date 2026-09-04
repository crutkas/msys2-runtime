#!/bin/bash
export PATH=/root/xc/inst/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
W=/root/xc/inst/aarch64-pc-cygwin/include/w32api
echo "=== basetsd.h lines 1..70 ==="
sed -n '1,70p' $W/basetsd.h
echo
echo "=== mbstate_t definitions visible ==="
grep -rn 'mbstate_t' $W/_mingw.h $W/wchar.h 2>/dev/null | head -20
sed -n '80,92p' /root/xc/runtime/newlib/libc/include/wchar.h
