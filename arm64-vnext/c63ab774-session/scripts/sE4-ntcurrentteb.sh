#!/bin/bash
R=/root/xc/w-link/runtime/winsup/cygwin
W=/root/xc/inst/aarch64-pc-cygwin/include/w32api
echo "############ NtCurrentTeb definition(s) visible to the build ############"
grep -rn -B2 -A12 'NtCurrentTeb' $W/winnt.h | head -40
echo
echo "############ does winsup define its own? ############"
grep -rn 'NtCurrentTeb' $R/local_includes/ntdll.h | head -5
echo
echo "############ what does the COMPILER actually emit for NtCurrentTeb? ############"
export PATH=/root/xc/inst/bin:$PATH
cat > /tmp/teb2.c <<'EOF'
#include <windows.h>
void *get_teb (void) { return NtCurrentTeb (); }
void *get_stackbase (void) { return NtCurrentTeb ()->Tib.StackBase; }
EOF
aarch64-pc-cygwin-gcc -O2 -S -o /tmp/teb2.s /tmp/teb2.c \
  -isystem $W -isystem /root/xc/bld/newlib/targ-include \
  -isystem /root/xc/w-link/runtime/newlib/libc/include 2>&1 | head -5
echo "--- get_teb ---"
sed -n '/^get_teb:/,/ret/p' /tmp/teb2.s | head -12
echo "--- get_stackbase ---"
sed -n '/^get_stackbase:/,/ret/p' /tmp/teb2.s | head -12
echo
echo "=== does it use x18 or tpidr_el0? ==="
printf 'x18       : %s\n' "$(grep -c 'x18' /tmp/teb2.s)"
printf 'tpidr_el0 : %s\n' "$(grep -c 'tpidr_el0' /tmp/teb2.s)"
