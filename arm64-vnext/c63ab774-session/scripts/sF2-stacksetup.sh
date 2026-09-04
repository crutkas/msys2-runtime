#!/bin/bash
R=/root/xc/w-link/runtime/winsup/cygwin
echo "############ the faulting instruction is a STACK PROBE ############"
cat <<'EOF'
  1800efb9c <calloc>:
     1800efb9c:  sub  x10, sp, #0x2, lsl #12   // x10 = sp - 0x2000
     1800efba0:  str  xzr, [x10, #4032]        // <== FAULTED (probe sp-0x1040)
  A stack-clash / large-frame probe: touch a page below sp to fault the guard
  page in deliberately. It raised STATUS_STACK_OVERFLOW, so the memory below sp
  is NOT committed.

  SP at fault = 0x00000007FFE05030
  For comparison, an ordinary Windows thread stack measured on this host was
  0x801B000000-0x801B990000, and the DllMain-time SP was 0x000000AE64F1AEB0.
  0x7FFE05030 is NEITHER -- so by this point Cygwin has SWITCHED TO ITS OWN
  STACK, and the probe walks off the bottom of it.
EOF

echo
echo "############ dcrt0 main-thread stack setup ############"
sed -n '395,480p' $R/dcrt0.cc

echo
echo "############ any arch conditional in that region? ############"
awk 'NR>=380 && NR<=500 && /__x86_64__|__aarch64__|#else|#endif|#ifdef/ {print NR": "$0}' $R/dcrt0.cc
