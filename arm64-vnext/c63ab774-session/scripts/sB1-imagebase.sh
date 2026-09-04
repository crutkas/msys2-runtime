#!/bin/bash
export PATH=/root/xc/inst/bin:$PATH
L=/root/xc/w-link
echo "############ image base handling in cygwin.sc ############"
grep -n 'image_base\|__image_base__\|ImageBase' $L/bld/winsup/cygwin/cygwin.sc | head
head -20 $L/bld/winsup/cygwin/cygwin.sc

echo
echo "############ what does ld default __image_base__ to for aarch64pe? ############"
aarch64-pc-cygwin-ld --verbose 2>/dev/null | grep -i 'image_base' | head -3

echo
echo "############ section VMAs of the fixed-base DLL ############"
aarch64-pc-cygwin-objdump -h $L/bld/winsup/cygwin/new-msys-2.0-fixedbase.dll 2>/dev/null | head -8

echo
echo "############ is a .reloc section still present? ############"
aarch64-pc-cygwin-objdump -h $L/bld/winsup/cygwin/new-msys-2.0-fixedbase.dll 2>/dev/null | grep -c reloc
