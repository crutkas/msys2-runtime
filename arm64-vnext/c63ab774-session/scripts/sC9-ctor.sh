#!/bin/bash
# The fault is a blr through a value loaded from the CTOR list.
# cygwin.sc builds that list with LONG(...) markers -- LONG is 4 BYTES.
# On a 64-bit target the head marker and terminator must be 8 bytes.
L=/root/xc/w-link
echo "############ cygwin.sc.in : CTOR/DTOR list construction ############"
grep -n -B3 -A6 'CTOR_LIST__' $L/runtime/winsup/cygwin/cygwin.sc.in

echo
echo "############ the GENERATED aarch64 cygwin.sc ############"
grep -n -A3 'CTOR_LIST__\|DTOR_LIST__' $L/bld/winsup/cygwin/cygwin.sc

echo
echo "############ byte arithmetic ############"
cat <<'EOF'
  x86_64 branch : LONG(-1); LONG(-1); ... LONG(0); LONG(0);   = 8 bytes each
  aarch64 branch: LONG(-1);            ... LONG(0);           = 4 bytes each

  With 4-byte markers the 8-byte ctor pointers are MISALIGNED by 4, and the
  terminator is only half a pointer wide. The backward walk

      ldr x0, [x19], #-8
      blr x0

  eventually loads an 8-byte window straddling the 4-byte ctor terminator
  LONG(0) and the 4-byte dtor head marker LONG(-1):

      [00 00 00 00][FF FF FF FF]  little-endian  =  0xFFFFFFFF00000000

  which is EXACTLY the faulting branch target.
EOF
