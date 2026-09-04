#!/bin/bash
# Quantify: how many .autoload_text absolute quads have DIR64 base relocations?
export PATH=/root/xc/inst/bin:$PATH
D=/root/xc/w-link/bld/winsup/cygwin/new-msys-2.0.dll

SEC_RVA=0x218000
SEC_END=$((0x218000 + 0x5060))
printf 'section .autoload_text : RVA 0x%X .. 0x%X  (size 0x5060)\n' $SEC_RVA $SEC_END

echo
echo "############ thunks in the section ############"
N=$(aarch64-pc-cygwin-objdump -d --start-address=$((0x180218000)) --stop-address=$((0x180218000+0x5060)) $D 2>/dev/null \
    | grep -cE '^0000000180[0-9a-f]+ <[A-Za-z_][A-Za-z0-9_]*>:')
echo "named thunk entry points : $N"
echo "each thunk has 2 absolute quads (info ptr @2:, resolved addr @3:)"
echo "so quads needing DIR64   : $((N*2))"

echo
echo "############ DIR64 fixups actually present in that RVA range ############"
aarch64-pc-cygwin-objdump -p $D 2>/dev/null \
  | grep -oE 'reloc +[0-9]+ offset +[0-9a-f]+ \[([0-9a-f]+)\] DIR64' \
  | grep -oE '\[[0-9a-f]+\]' | tr -d '[]' > /tmp/allrel.txt
TOT=$(wc -l < /tmp/allrel.txt)
IN=$(awk -v a=$SEC_RVA -v b=$SEC_END 'strtonum("0x"$1)>=a && strtonum("0x"$1)<b' /tmp/allrel.txt | wc -l)
echo "DIR64 fixups in whole image        : $TOT"
echo "DIR64 fixups inside .autoload_text : $IN"
echo "MISSING                            : $(( N*2 - IN ))"

echo
echo "############ is the FIRST thunk's slot relocated? ############"
echo "first thunk CheckTokenMembership at 0x180218000; its quads at RVA 0x218030 and 0x218040"
for r in 218030 218040; do
  if grep -qx "$r" /tmp/allrel.txt; then echo "  0x$r : HAS DIR64"; else echo "  0x$r : NO RELOCATION  <<<"; fi
done

echo
echo "############ which thunks DO have relocs? ############"
awk -v a=$SEC_RVA -v b=$SEC_END 'strtonum("0x"$1)>=a && strtonum("0x"$1)<b' /tmp/allrel.txt | sort | head -8
echo "..."
awk -v a=$SEC_RVA -v b=$SEC_END 'strtonum("0x"$1)>=a && strtonum("0x"$1)<b' /tmp/allrel.txt | sort | tail -4

echo
echo "############ what section are those in, really? ############"
aarch64-pc-cygwin-objdump -h $D | awk '$4 ~ /^0000000180/ {print $2, $3, $4}' | head -20
