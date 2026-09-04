#!/bin/bash
# Crash was: READ of address 0x8, at 0x00007FFDAFB32A34.
# Earlier map-only load put the image at 0x00007FFDAFAA0000 -> RVA 0x92A34.
export PATH=/root/xc/inst/bin:$PATH
D=/root/xc/w-link/bld/winsup/cygwin/new-msys-2.0.dll
VA=$((0x180000000 + 0x92A34))
printf 'target VMA: 0x%X\n\n' $VA
echo "############ disassembly around the faulting instruction ############"
aarch64-pc-cygwin-objdump -d --start-address=$((VA-0x40)) --stop-address=$((VA+0x20)) $D 2>/dev/null | tail -30

echo
echo "############ which function is that? ############"
aarch64-pc-cygwin-objdump -d --start-address=$((VA-0x200)) --stop-address=$((VA+0x20)) $D 2>/dev/null \
  | grep -E '^0000|<[^>]*>:' | tail -5

echo
echo "############ how does sigfe.s access the TEB? ############"
grep -n -m3 -B2 -A6 'tpidr_el0\|x18' /root/xc/w-link/bld/winsup/cygwin/sigfe.s | head -40

echo
echo "############ counts in sigfe.s ############"
printf 'mrs .* tpidr_el0 : %s\n' "$(grep -c 'tpidr_el0' /root/xc/w-link/bld/winsup/cygwin/sigfe.s)"
printf 'references to x18: %s\n' "$(grep -c '\bx18\b' /root/xc/w-link/bld/winsup/cygwin/sigfe.s)"
