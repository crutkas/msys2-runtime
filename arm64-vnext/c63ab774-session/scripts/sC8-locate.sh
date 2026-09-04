#!/bin/bash
# LR = RVA 0x83B8 in the module -> the branch instruction is at RVA 0x83B4.
# Module base at fault time was 0x7FFDB10B0000 (from VirtualQuery, NOT assumed).
# The image's own ImageBase is 0x180040000, so file VA = 0x180040000 + RVA.
export PATH=/root/xc/inst/bin:$PATH
D=/root/xc/w-link/bld/winsup/cygwin/new-msys-2.0.dll
VA=$((0x180040000 + 0x83B8))
printf 'LR RVA 0x83B8 -> file VA 0x%X\n' $VA
printf 'branching insn at RVA 0x83B4 -> file VA 0x%X\n\n' $((VA-4))

echo "############ disassembly around the branch ############"
aarch64-pc-cygwin-objdump -d --start-address=$((VA-0x60)) --stop-address=$((VA+0x18)) $D 2>/dev/null | tail -30

echo
echo "############ which function contains it? ############"
aarch64-pc-cygwin-objdump -d --start-address=$((VA-0x400)) --stop-address=$((VA+0x8)) $D 2>/dev/null \
  | grep -E '>:$' | tail -3

echo
echo "############ nearest preceding symbol ############"
aarch64-pc-cygwin-nm -n $D 2>/dev/null | awk -v t=$VA 'strtonum("0x"$1)<=t && $2 ~ /[Tt]/ {last=$0} END{print last}'
