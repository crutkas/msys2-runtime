#!/bin/bash
# What ARE the 10 survivors? They sit at 0x21bdd0/0x21bdd8, 0x21be00/0x21be08 ...
# -- pairs 8 bytes apart, whereas thunk quads are 0x10 apart (0x218030/0x218040).
# That spacing difference suggests they are NOT thunk slots at all.
export PATH=/root/xc/inst/bin:$PATH
D=/root/xc/w-link/bld/winsup/cygwin/new-msys-2.0.dll

echo "############ disassembly around the first survivor (0x18021bdd0) ############"
aarch64-pc-cygwin-objdump -d --start-address=$((0x18021bd80)) --stop-address=$((0x18021be20)) $D 2>/dev/null | tail -30

echo
echo "############ which symbol owns that region? ############"
aarch64-pc-cygwin-nm -n $D 2>/dev/null | awk '$1!=""' | awk 'strtonum("0x"$1)<=0x18021bdd0' | tail -3

echo
echo "############ spacing check ############"
echo "thunk quad pairs   : 0x218030 / 0x218040   -> 0x10 apart"
echo "survivor pairs     : 0x21bdd0 / 0x21bdd8   -> 0x08 apart"
echo "=> different structure, so the 10 are probably NOT thunk resolved-addr slots"
