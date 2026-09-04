#!/bin/bash
# Static comparison: C++ struct dll_info vs what LoadDLLprime's assembly emits.
L=/root/xc/w-link
R=$L/runtest 2>/dev/null
A=/root/xc/w-link/runtime/winsup/cygwin/autoload.cc
echo "############ the C++ struct(s) ############"
grep -n -B3 -A30 'struct dll_info' $A | head -50
echo
echo "############ struct func_info ############"
grep -n -B2 -A20 'struct func_info' $A | head -35
echo
echo "############ any static_assert on offsets? ############"
grep -n -A4 '_Static_assert\|static_assert' $A | head -30
