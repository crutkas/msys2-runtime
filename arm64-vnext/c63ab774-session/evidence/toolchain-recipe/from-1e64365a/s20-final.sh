#!/bin/bash
L=/root/xc/winsup-build5.log
LA=/root/xc/winsup-build4.log
echo "=========== RUN B: exact error for each failing target ==========="
grep -n 'error:\|No rule to make target' $L | sed 's/^[0-9]*://' | sort -u
echo
echo "=========== autoload.o failure reason (run B) ==========="
grep -n -B8 'autoload.o] Error' $L | head -25
echo
echo "=========== thread.o failure reason (run B) ==========="
grep -n -B8 'thread.o] Error' $L | head -20
echo
echo "=========== devices.cc failure reason ==========="
grep -n -B8 'devices.cc] Error' $L | head -20
echo
echo "=========== did sigfe.s / cygwin.sc succeed now? ==========="
grep -n 'cygwin.sc\|sigfe' $L | head -10
ls -l /root/xc/bld/winsup/cygwin/cygwin.sc /root/xc/bld/winsup/cygwin/sigfe.s 2>&1
echo
echo "=========== RUN A (Werror on): exact errors ==========="
grep -n 'error:' $LA | sed 's/^[0-9]*://' | sort -u
