#!/bin/bash
L=/root/xc/wb-r6.log
echo "===== thread.o ====="
grep -n -B12 'thread.o\] Error' $L | head -25
echo
echo "===== autoload.o ====="
grep -n -B12 'autoload.o\] Error' $L | head -25
echo
echo "===== devices.cc ====="
grep -n -B10 'devices.cc\] Error' $L | head -20
echo
echo "===== sigfe.s / cygwin.sc state ====="
ls -l /root/xc/bld/winsup/cygwin/sigfe.s /root/xc/bld/winsup/cygwin/cygwin.sc /root/xc/bld/winsup/cygwin/*.def 2>&1
echo
echo "===== all Error targets ====="
grep -o "\*\*\* \[[^]]*\] Error [0-9]*" $L | sort -u
