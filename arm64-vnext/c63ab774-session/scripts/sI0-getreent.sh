#!/bin/bash
# Direct runtime measurement of __getreent() versus StackBase on ARM64.
# Verifying the source has the subtraction is NOT the same as verifying the
# emitted code performs it, nor that the runtime value is right. Measure it.
set -u
export PATH=/root/xc/inst/bin:$PATH
L=/root/xc/w-link
R=$L/runtime/winsup/cygwin
B=$L/bld/winsup/cygwin
D=/mnt/c/Users/crutkasLocal/.copilot/session-state/c63ab774-a023-4e57-9bc4-53f727507ada/files/runtest
cd $B || exit 1

cat > /tmp/rung11.c <<'EOF'
#include <stdio.h>

struct _reent;
extern struct _reent *__getreent (void);

int
main (void)
{
  void *teb, *stackbase, *reent;

  /* Read the TEB from x18 exactly as the runtime does, then NT_TIB.StackBase
     from [x18+8]. */
  __asm__ __volatile__ ("mov %0, x18" : "=r" (teb));
  stackbase = *(void **) ((char *) teb + 8);
  reent = (void *) __getreent ();

  printf ("x18 (TEB)        = %p\n", teb);
  printf ("StackBase [x18+8]= %p\n", stackbase);
  printf ("__getreent()     = %p\n", reent);
  printf ("difference       = %lld\n",
          (long long) ((char *) stackbase - (char *) reent));
  printf ("expected         = 12800 (__CYGTLS_PADSIZE__)\n");
  if ((char *) stackbase - (char *) reent == 12800)
    printf ("VERDICT: CORRECT - subtraction is performed\n");
  else if (reent == stackbase)
    printf ("VERDICT: DEFECTIVE - returns RAW StackBase\n");
  else
    printf ("VERDICT: UNEXPECTED difference\n");
  fflush (stdout);
  return 0;
}
EOF

aarch64-pc-cygwin-gcc -g -O0 -nostdlib -nostartfiles \
  -isystem $R/include -isystem /root/xc/bld/newlib/targ-include \
  -isystem $L/runtime/newlib/libc/include \
  -o rung11.exe $B/crt0.o /tmp/rung11.c $B/libmsys-2.0.a \
  -L/root/xc/build-gcc2/aarch64-pc-cygwin/libgcc -lgcc \
  -L/root/xc/implibs/lib -lkernel32 2>&1 | head -6
echo "LINK EXIT ${PIPESTATUS[0]}"
[ -f rung11.exe ] && cp rung11.exe $D/ && echo staged
