#!/bin/bash
export PATH=/root/xc/inst/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
cd /root/xc/bld/winsup/cygwin
INC=$(sed -n 's/^AM_CPPFLAGS = //p' Makefile | head -1)
for t in thread.o lib/_cygwin_crt0_common.o; do
  echo "########## $t ##########"
  make $t INCLUDES="$INC" CFLAGS="-g -O2 -Wno-error" CXXFLAGS="-g -O2 -Wno-error" 2>&1 | grep -m4 'error:\|Error'
done
echo
echo "########## sigfe.s content (0 bytes?) ##########"
wc -c sigfe.s; echo "--- gendef aarch64 handling ---"
grep -n 'aarch64\|x86_64\|cpu' /root/xc/runtime/winsup/cygwin/scripts/gendef | head -20
