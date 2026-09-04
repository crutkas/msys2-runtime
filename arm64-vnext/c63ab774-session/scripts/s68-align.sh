#!/bin/bash
export PATH=/root/xc/inst/bin:$PATH
L=/root/xc/w-link/bld/winsup/cygwin
echo "############ the paired LDR carrying PAGEOFFSET_12L ############"
aarch64-pc-cygwin-objdump -dr --start-address=0xb60 --stop-address=0xbb0 $L/exceptions.o 2>/dev/null \
  | grep -A2 -B2 'PAGEOFFSET\|PAGEBASE\|adrp\|ldr'  | head -30

echo
echo "############ where did __imp_Rtl* actually land? (from the map) ############"
grep -n '__imp_RtlLookupFunctionEntry\|__imp_RtlCaptureContext\|__imp_RtlVirtualUnwind' $L/msys.map 2>/dev/null | head -6

echo
echo "############ .idata layout in the map ############"
grep -n -A3 '^\.idata' $L/msys.map 2>/dev/null | head -20
grep -n 'idata\$4\|idata\$5' $L/msys.map 2>/dev/null | head -8
