#!/bin/bash
# TEST 1: are the 10 relocated quads structurally different from the 414?
# TEST 2: x86_64 differential -- does the x86_64 thunk use PC-relative addressing
#         (needing no base relocation) rather than absolute .quad?
export PATH=/root/xc/inst/bin:$PATH
L=/root/xc/w-link
R=$L/runtime/winsup/cygwin

echo "############ TEST 2 first: the x86_64 thunk construct ############"
sed -n '117,152p' $R/autoload.cc

echo
echo "############ where does LoadDLLprime put .<dll>_info? ############"
echo "--- x86_64 variant (70-91) ---"
sed -n '70,91p' $R/autoload.cc
echo "--- aarch64 variant (92-112) ---"
sed -n '92,112p' $R/autoload.cc
