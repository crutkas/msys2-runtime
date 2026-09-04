#!/bin/bash
cd /root/xc/bld/winsup/cygwin
echo "=== AM_CPPFLAGS ==="
sed -n 's/^AM_CPPFLAGS = //p' Makefile | head -1 | tr ' ' '\n' | head -30
echo
echo "=== does it contain the include dir with cygwin/version.h? ==="
ls /root/xc/runtime/winsup/cygwin/include/cygwin/version.h
echo
echo "=== mkvers.sh windres invocation ==="
grep -n 'windres\|WINDRES\|\$@\|shift' /root/xc/runtime/winsup/cygwin/scripts/mkvers.sh | head -30
echo
echo "=== actual failing line in log ==="
grep -n -B3 -A3 'winver.rc' /root/xc/wb-r8.log | head -20
