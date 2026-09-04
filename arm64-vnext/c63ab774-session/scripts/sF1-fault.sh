#!/bin/bash
export PATH=/root/xc/inst/bin:$PATH
D=/root/xc/w-link/bld/winsup/cygwin/new-msys-2.0.dll
VA=$((0x180040000 + 0xAFBA0))
LRVA=$((0x180040000 + 0xAFBD8))
printf 'fault PC RVA 0xAFBA0 -> file VA 0x%X\n' $VA
printf 'LR       RVA 0xAFBD8 -> file VA 0x%X   (delta 0x38)\n\n' $LRVA

echo "############ disassembly around the fault ############"
aarch64-pc-cygwin-objdump -d --start-address=$((VA-0x60)) --stop-address=$((VA+0x60)) $D 2>/dev/null | tail -40

echo
echo "############ containing symbol ############"
aarch64-pc-cygwin-nm -n $D 2>/dev/null \
  | awk -v t=$VA 'toupper($2) ~ /^[TW]$/ { a=strtonum("0x" $1); if (a<=t) l=$0 } END { print l }'

echo
echo "############ function label from objdump ############"
aarch64-pc-cygwin-objdump -d --start-address=$((VA-0x600)) --stop-address=$((VA+0x8)) $D 2>/dev/null \
  | grep -E '>:$' | tail -4
