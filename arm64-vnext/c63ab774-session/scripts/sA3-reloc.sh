#!/bin/bash
# Does .reloc cover the .autoload_text quads? The image WAS relocated
# (loaded at 0x7FFDAD3D0000, not the preferred 0x180000000), so every absolute
# .quad in a thunk needs a DIR64 base relocation or it will still hold the
# unrelocated 0x1802... value.
export PATH=/root/xc/inst/bin:$PATH
D=/root/xc/w-link/bld/winsup/cygwin/new-msys-2.0.dll

echo "############ reloc blocks covering .autoload_text (RVA 0x218000-0x21D060) ############"
aarch64-pc-cygwin-objdump -p $D 2>/dev/null \
  | awk '/^Virtual Address:/{va=strtonum("0x"$3)} /^Virtual Address:/ && va>=0x218000 && va<0x21e000 {print}' | head

echo
echo "--- all distinct reloc block VAs, sorted ---"
aarch64-pc-cygwin-objdump -p $D 2>/dev/null | awk '/^Virtual Address:/{print $3}' | sort -u > /tmp/relocvas.txt
wc -l < /tmp/relocvas.txt
echo "first 6:"; head -6 /tmp/relocvas.txt
echo "last 6:";  tail -6 /tmp/relocvas.txt
echo
echo -n "any block in [00218000,0021e000)? : "
awk 'strtonum("0x"$1)>=0x218000 && strtonum("0x"$1)<0x21e000' /tmp/relocvas.txt | tr '\n' ' '
echo "(blank == NONE)"

echo
echo "############ DIR64 fixups inside .autoload_text ############"
aarch64-pc-cygwin-objdump -p $D 2>/dev/null | grep -E 'reloc .* \[21[89abcd]' | head -10
echo "(blank == the thunk quads are NOT relocated)"

echo
echo "############ for contrast, a section that IS relocated ############"
aarch64-pc-cygwin-objdump -p $D 2>/dev/null | grep -m3 'DIR64'

echo
echo "############ does the object file carry the reloc before linking? ############"
aarch64-pc-cygwin-objdump -r /root/xc/w-link/bld/winsup/cygwin/autoload.o 2>/dev/null \
  | grep -c 'ADDR64\|DIR64\|SECREL'
aarch64-pc-cygwin-objdump -r /root/xc/w-link/bld/winsup/cygwin/autoload.o 2>/dev/null | head -12
