#!/bin/bash
export PATH=/root/xc/inst/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
W=/root/xc/inst/aarch64-pc-cygwin/include/w32api
BLD=/root/xc/bld
echo "=== corecrt.h mbstate_t guard ==="
sed -n '140,160p' $W/corecrt.h
echo
cd $BLD/winsup/cygwin
INC=$(sed -n 's/^AM_CPPFLAGS = //p' Makefile | head -1)
find $BLD/winsup/cygwin -name '*.o' -delete
ulimit -u 4096
time make -k -j12 INCLUDES="$INC" > /root/xc/winsup-build2.log 2>&1
echo "MAKE_EXIT=$?"
echo "=================== SUMMARY (after _WIN64 fix) ==================="
echo "objects (.o) produced: $(find $BLD/winsup/cygwin -name '*.o' | wc -l)"
echo "total 'error:' lines: $(grep -c 'error:' /root/xc/winsup-build2.log)"
echo "failed targets: $(grep -c '^make\[1\]: \*\*\* \[' /root/xc/winsup-build2.log)"
echo
echo "=================== UNIQUE ERROR MESSAGES (normalised) ==================="
grep -o 'error: .*' /root/xc/winsup-build2.log | sed 's/[0-9]\+/N/g' | sort | uniq -c | sort -rn | head -30
echo
echo "=================== FAILED TARGETS ==================="
grep -o '^make\[1\]: \*\*\* \[[^]]*\]' /root/xc/winsup-build2.log | sed 's/.*: //' | sort -u | head -40
