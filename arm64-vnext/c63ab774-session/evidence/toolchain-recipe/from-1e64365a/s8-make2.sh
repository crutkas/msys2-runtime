#!/bin/bash
export PATH=/root/xc/inst/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
BLD=/root/xc/bld
cd $BLD/winsup/cygwin
ls /root/xc/runtime/winsup/cygwin/include/sys/termios.h /root/xc/runtime/winsup/cygwin/include/sys/resource.h 2>&1
INC=$(sed -n 's/^AM_CPPFLAGS = //p' Makefile | head -1)
echo "INC=$INC"
ulimit -u 4096
time make -k -j12 V=1 INCLUDES="$INC" > /root/xc/winsup-build.log 2>&1
echo "MAKE_EXIT=$?"
echo "=================== SUMMARY ==================="
echo "objects (.o) produced: $(find $BLD/winsup/cygwin -name '*.o' | wc -l)"
echo "distinct source files with errors: $(grep -o '[^ ]*\.\(cc\|c\|h\|S\):[0-9]*:[0-9]*: error' /root/xc/winsup-build.log | cut -d: -f1 | sort -u | wc -l)"
echo "total error: lines: $(grep -c 'error:' /root/xc/winsup-build.log)"
echo "=================== FIRST 60 ERRORS ==================="
grep -n 'error:\|Error [0-9]\|No rule to make' /root/xc/winsup-build.log | head -60
