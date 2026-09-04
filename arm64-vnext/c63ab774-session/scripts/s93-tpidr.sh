#!/bin/bash
# Where does the "mrs tpidr_el0 / ldr [x,#8]" TEB idiom come from?
L=/root/xc/w-link
R=$L/runtime/winsup/cygwin
echo "############ tpidr_el0 in the runtime sources ############"
grep -rn 'tpidr_el0' $R --include=*.h --include=*.cc --include=*.c 2>/dev/null | head -20

echo
echo "############ _tlsbase / _tlstop definitions ############"
grep -rn '_tlsbase\|_tlstop' $R/local_includes/cygtls.h $R/local_includes/*.h 2>/dev/null | head -20

echo
echo "############ the x86_64 vs aarch64 branch ############"
grep -rn -B6 -A14 'tpidr_el0' $R/local_includes/cygtls.h 2>/dev/null | head -40

echo
echo "############ how many times does the DLL use this idiom? ############"
export PATH=/root/xc/inst/bin:$PATH
D=$L/bld/winsup/cygwin/new-msys-2.0.dll
printf 'mrs tpidr_el0 occurrences in .text : '
aarch64-pc-cygwin-objdump -d $D 2>/dev/null | grep -c 'mrs.*tpidr_el0'

echo
echo "############ does Windows ARM64 use x18 instead? (documented ABI) ############"
cat <<'EOF'
  Windows on Arm ABI: x18 IS the TEB pointer, reserved as the "platform register".
  tpidr_el0 is the ELF/Linux TLS register; Windows does NOT populate it for
  user-mode threads, so `mrs xN, tpidr_el0` yields 0 and `ldr [xN, #8]` reads
  address 0x8 -- precisely the captured fault (READ of 0x0000000000000008).
EOF
