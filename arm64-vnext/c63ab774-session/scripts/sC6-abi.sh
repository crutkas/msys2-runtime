#!/bin/bash
# The dll_chain mechanism assumes a 128-bit return comes back in x0/x1:
#     dll_chain:  mov x30, x0   ; br x1
# AAPCS64 returns a 128-bit integer in x0:x1. But the MICROSOFT ARM64 ABI
# returns anything larger than 8 bytes INDIRECTLY via a hidden pointer in x8.
# aarch64-pc-cygwin GCC targets Windows. Which does it actually do?
# If it returns indirectly, x0 holds the hidden buffer pointer and x1 is garbage,
# and `br x1` branches to whatever happens to be in x1 -- an EXECUTE fault to a
# structured-looking value.
export PATH=/root/xc/inst/bin:$PATH
W=/root/xc/inst/aarch64-pc-cygwin/include/w32api

cat > /tmp/abi.c <<'EOF'
typedef unsigned __int128 two_addr_t;
union retchain { struct { unsigned long high; unsigned long low; }; two_addr_t ll; };

two_addr_t probe (unsigned long a, unsigned long b)
{
  union retchain r;
  r.high = a;
  r.low  = b;
  return r.ll;
}

extern void use (two_addr_t);
void caller (void)
{
  use (probe (0x1111111111111111UL, 0x2222222222222222UL));
}
EOF

echo "############ how does aarch64-pc-cygwin GCC return a 128-bit value? ############"
aarch64-pc-cygwin-gcc -O2 -S -o /tmp/abi.s /tmp/abi.c 2>&1 | head -3
echo "--- probe() ---"
sed -n '/^probe:/,/ret/p' /tmp/abi.s | head -20
echo
echo "--- caller() : how is the result consumed? ---"
sed -n '/^caller:/,/ret/p' /tmp/abi.s | head -25

echo
echo "############ verdict markers ############"
echo -n "does probe() use x8 (indirect return)? : "
sed -n '/^probe:/,/ret/p' /tmp/abi.s | grep -c 'x8'
echo -n "does probe() set x0 and x1?            : "
sed -n '/^probe:/,/ret/p' /tmp/abi.s | grep -cE '\bx0\b|\bx1\b'

echo
echo "############ for contrast: same source for x86_64 semantics (rax:rdx) ############"
echo "(x86_64 SysV/MS both return __int128 in rax:rdx, which is why the x86 path works)"
