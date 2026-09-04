#!/bin/bash
export PATH=/root/xc/inst/bin:$PATH
L=/root/xc/w-link/bld/winsup/cygwin
echo "############ how does cygwin.sc lay out .idata? ############"
grep -n -A12 '\.idata' $L/cygwin.sc

echo
echo "############ the aarch64 branch of cygwin.sc.in ############"
sed -n '1,30p' /root/xc/w-link/runtime/winsup/cygwin/cygwin.sc.in

echo
echo "############ the failing instruction: what does it look like? ############"
aarch64-pc-cygwin-objdump -d --start-address=0xb60 --stop-address=0xbe0 \
  $L/exceptions.o 2>/dev/null | sed -n '1,40p'

echo
echo "############ reloc entries for __imp_Rtl* in exceptions.o ############"
aarch64-pc-cygwin-objdump -r $L/exceptions.o 2>/dev/null | grep -i 'imp_Rtl' | head -12
