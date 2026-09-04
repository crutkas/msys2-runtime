#!/bin/bash
export PATH=/root/xc/inst/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
W=/root/xc/inst/aarch64-pc-cygwin/include/w32api
BLD=/root/xc/bld
# POINTER_64_INT width (cosmetic but keep it consistent with a 64-bit target)
sed -i 's|^#if (defined (__x86_64__) || defined (__ia64__)) \&\& !(defined (__WIDL__) || defined (RC_INVOKED))$|#if (defined (__x86_64__) || defined (__ia64__) || defined (__aarch64__)) \&\& !(defined (__WIDL__) || defined (RC_INVOKED))|' $W/basetsd.h
sed -n '9,12p' $W/basetsd.h
echo "=== verify UINT_PTR==8 and mbstate_t clean ==="
cd /root/xc/t
cat > probe2.c <<'EOF'
#include <w32api/windows.h>
#include <wchar.h>
char a[sizeof(UINT_PTR)==8 ? 1 : -1];
char b[sizeof(void*)==8 ? 1 : -1];
char c[sizeof(long)==8 ? 1 : -1];
EOF
aarch64-pc-cygwin-gcc -c probe2.c -o probe2.o \
  -isystem /root/xc/runtime/winsup/cygwin/include \
  -isystem /root/xc/bld/newlib/targ-include \
  -isystem /root/xc/runtime/newlib/libc/include 2>&1 | head -10
echo "PROBE2_DONE"

cd $BLD/winsup/cygwin
INC=$(sed -n 's/^AM_CPPFLAGS = //p' Makefile | head -1)
find $BLD/winsup/cygwin -name '*.o' -delete
ulimit -u 4096
time make -k -j12 INCLUDES="$INC" > /root/xc/winsup-build3.log 2>&1
echo "MAKE_EXIT=$?"
echo "=========== SUMMARY (w32api v12.0.0 + aarch64 _WIN64 fix) ==========="
echo "objects (.o) produced: $(find $BLD/winsup/cygwin -name '*.o' | wc -l)"
echo "total 'error:' lines: $(grep -c 'error:' /root/xc/winsup-build3.log)"
echo "failed targets:        $(grep -o '^make\[1\]: \*\*\* \[[^]]*\]' /root/xc/winsup-build3.log | sort -u | wc -l)"
echo
echo "=========== UNIQUE ERROR MESSAGES ==========="
grep -o 'error: .*' /root/xc/winsup-build3.log | sed 's/[0-9]\+/N/g' | sort | uniq -c | sort -rn | head -40
