#!/bin/bash
# Finish Priority 1: is aarch64-pc-msys actually buildable, and what does __MSYS__ change?
G=/root/xc/gcc-src
L=/root/xc/w-link

echo "############ what did 'not supported in subdirectories' cover? ############"
grep -n -A6 'not supported in the following subdirectories' /tmp/msystest/cfg.log

echo
echo "############ does config.gcc have a fallback for unknown targets? ############"
grep -n -A6 '^\s*\*)' $G/gcc/config.gcc | tail -12

echo
echo "############ live: can cc1 even be configured for msys? ############"
ls -d /tmp/msystest/gcc 2>/dev/null && echo "gcc subdir configured" || echo "NO gcc subdir -> compiler cannot be built for this target"

echo
echo "############ the aarch64 cygwin case in config.gcc ############"
sed -n '1275,1290p' $G/gcc/config.gcc

echo
echo "############ WHAT DO THE 40 __MSYS__ SITES ACTUALLY CHANGE? ############"
for f in environ.cc fhandler/pty.cc mm/cygheap.cc uname.cc syslog.cc dtable.cc dll_init.cc dlfcn.cc hookapi.cc fhandler/pipe.cc; do
  p=$L/runtime/winsup/cygwin/$f
  [ -f "$p" ] || continue
  echo "---- $f ----"
  grep -n -A2 '#ifdef __MSYS__\|#if defined *(__MSYS__)' "$p" | head -8
done

echo
echo "############ version.h: what changes? ############"
sed -n '508,540p' $L/runtime/winsup/cygwin/include/cygwin/version.h
