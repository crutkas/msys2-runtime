#!/bin/bash
# Rung 8: a process that does normal cygheap work then DELIBERATELY faults, so
# a debugger can capture a context late in life and walk cygheap->chain.
# PURPOSE: decide whether the broken chain terminator is a FORK defect or a
# pre-existing cygheap defect present in every process.
set -u
export PATH=/root/xc/inst/bin:$PATH
L=/root/xc/w-link
R=$L/runtime/winsup/cygwin
B=$L/bld/winsup/cygwin
D=/mnt/c/Users/crutkasLocal/.copilot/session-state/c63ab774-a023-4e57-9bc4-53f727507ada/files/runtest
cd $B || exit 1

cat > /tmp/rung8.c <<'EOF'
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
int
main (void)
{
  /* Do ordinary work so the cygheap is populated exactly as usual. */
  printf ("pid=%d\n", (int) getpid ());
  void *p = malloc (128);
  free (p);
  fflush (stdout);
  /* Deliberate fault: gives the debugger a context late in process life.
     NOT a defect under test -- it is the capture mechanism. */
  * (volatile int *) 0 = 1;
  return 0;
}
EOF

aarch64-pc-cygwin-gcc -g -O0 -nostdlib -nostartfiles \
  -isystem $R/include -isystem /root/xc/bld/newlib/targ-include \
  -isystem $L/runtime/newlib/libc/include \
  -o rung8.exe $B/crt0.o /tmp/rung8.c $B/libmsys-2.0.a \
  -L/root/xc/build-gcc2/aarch64-pc-cygwin/libgcc -lgcc \
  -L/root/xc/implibs/lib -lkernel32 2>&1 | head -5
echo "LINK EXIT ${PIPESTATUS[0]}"
[ -f rung8.exe ] && cp rung8.exe $D/ && echo "staged rung8.exe"
