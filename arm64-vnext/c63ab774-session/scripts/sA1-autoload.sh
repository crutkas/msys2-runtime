#!/bin/bash
# Test the hypothesis: 0xFFFFFFFF00000000 == 0xFFFFFFFF << 32, a 32-bit sentinel
# landing in the HIGH half of a 64-bit pointer. Inspect the autoload thunk's
# sentinel width and its patch offset on the aarch64 path.
L=/root/xc/w-link
R=$L/runtime/winsup/cygwin
echo "############ struct func_info / sentinel ############"
grep -n -B4 -A24 'struct func_info' $R/autoload.cc | head -45

echo
echo "############ the aarch64 LoadDLLfuncEx3 thunk (151-200) ############"
sed -n '151,200p' $R/autoload.cc

echo
echo "############ the x86_64 one for comparison (125-151) ############"
sed -n '125,151p' $R/autoload.cc
