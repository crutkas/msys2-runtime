#!/bin/bash
L=/root/xc/wb-r6.log
echo "===== thread.o real error ====="
awk '/CXX      thread.o/,0' $L | grep -m10 -i 'error\|warning: ' | head -10
grep -n 'thread.cc' $L | head -10
echo
echo "===== is devices.cc checked in? ====="
ls -la /root/xc/runtime/winsup/cygwin/devices.cc /root/xc/runtime/winsup/cygwin/devices.in 2>&1
echo "===== gendevices ====="
sed -n '1,40p' /root/xc/runtime/winsup/cygwin/scripts/gendevices
echo
echo "===== which shilka ====="
which shilka; apt-cache search shilka 2>/dev/null | head
