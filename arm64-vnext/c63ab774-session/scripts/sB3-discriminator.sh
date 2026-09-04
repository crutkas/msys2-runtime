#!/bin/bash
# Test the coordinator's hypothesis: is the surviving-10 count equal to the
# number of DISTINCT per-DLL ..._info symbols (i.e. one base relocation per
# unique TARGET SYMBOL rather than one per relocation SITE)?
export PATH=/root/xc/inst/bin:$PATH
L=/root/xc/w-link
R=$L/runtime/winsup/cygwin
D=$L/bld/winsup/cygwin/new-msys-2.0.dll

echo "############ distinct autoloaded DLLs in autoload.cc ############"
grep -oE 'LoadDLLprime *\( *[A-Za-z0-9_]+' $R/autoload.cc | awk '{print $NF}' | sed 's/.*(//' | sort -u > /tmp/dlls.txt
grep -oE '^ *LoadDLLfunc(Ex[0-9]?)? *\([^,]+, *([A-Za-z0-9_]+)' $R/autoload.cc \
  | sed 's/.*, *//' | sort -u > /tmp/dlls2.txt
cat /tmp/dlls.txt /tmp/dlls2.txt | sort -u | grep -v '^$' > /tmp/dllsall.txt
wc -l < /tmp/dllsall.txt
cat /tmp/dllsall.txt

echo
echo "############ distinct ..._info symbols actually in the image ############"
aarch64-pc-cygwin-nm $D 2>/dev/null | grep -oE '\.[a-z0-9_]+_info$' | sort -u > /tmp/infosyms.txt
wc -l < /tmp/infosyms.txt
cat /tmp/infosyms.txt

echo
echo "############ autoload_text sub-sections in the image ############"
aarch64-pc-cygwin-objdump -h $D 2>/dev/null | grep -c autoload_text
aarch64-pc-cygwin-objdump -h $D 2>/dev/null | grep autoload_text

echo
echo "############ THE 10 SURVIVORS: where exactly? ############"
aarch64-pc-cygwin-objdump -p $D 2>/dev/null \
  | grep -oE '\[([0-9a-f]+)\] DIR64' | tr -d '[]' | awk '{print $1}' > /tmp/allrel2.txt
awk 'strtonum("0x"$1)>=0x218000 && strtonum("0x"$1)<0x21d060' /tmp/allrel2.txt | sort -u
