#!/bin/bash
L=/root/xc/w-link
R=$L/runtime/winsup/cygwin
echo "############ how does the .din reference the dll_init pair? ############"
grep -n -B3 -A3 'dll_init\|detach_dll' $R/cygwin.din | head -30

echo
echo "############ gendef conditional handling ############"
grep -n 'ifdef\|ifndef\|endif\|__aarch64__\|__MSYS__\|cpu_defines\|%defines' $R/scripts/gendef | head -30

echo
echo "############ how is gendef invoked by the Makefile? ############"
grep -n 'gendef' $L/bld/winsup/cygwin/Makefile | head -5

echo
echo "############ what did msys.def actually get? ############"
grep -c . $L/bld/winsup/cygwin/msys.def
grep -n 'dll_init\|detach_dll' $L/bld/winsup/cygwin/msys.def | head
