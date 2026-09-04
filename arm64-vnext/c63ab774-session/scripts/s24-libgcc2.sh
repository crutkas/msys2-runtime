#!/bin/bash
# libgcc was configured --without-headers, so w32api's ctype.h is parsed with no
# definition of wint_t/wctype_t, breaking unwind-c.o / unwind-seh.o / unwind-sjlj.o.
# Supply newlib's target headers. libgcc's own default CFLAGS is "-g -O2".
export PATH=/root/xc/inst/bin:$PATH
cd /root/xc/build-gcc2/aarch64-pc-cygwin/libgcc || exit 1
INC="-isystem /root/xc/bld/newlib/targ-include -isystem /root/xc/runtime/newlib/libc/include -isystem /root/xc/runtime/winsup/cygwin/include"
timeout 1800 make -j12 libgcc.a CFLAGS="-g -O2 $INC" > /root/xc/libgcc-a2.log 2>&1
echo "MAKE EXIT $?"
echo "=== error summary ==="
grep 'error:' /root/xc/libgcc-a2.log | sed 's/^.*error: //' | sort | uniq -c | sort -rn | head -15
echo "=== failing targets ==="
grep -o "\*\*\* \[[^]]*\] Error" /root/xc/libgcc-a2.log | sort -u | head
echo "=== libgcc.a ==="
ls -la libgcc.a 2>&1
aarch64-pc-cygwin-objdump -f libgcc.a 2>/dev/null | head -4
