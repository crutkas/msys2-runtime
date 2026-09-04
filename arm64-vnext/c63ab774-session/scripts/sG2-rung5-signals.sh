#!/bin/bash
# Rung 5a: SIGNALS. First exercise of the 989 sigfe trampolines, which have
# been reproduced byte-identically by three sessions and have never once run.
#
# POLICY (from coordinator): freeze the artefact pair BEFORE any diagnosis.
# Address-level attribution against a moving binary is unsound by construction.
set -u
export PATH=/root/xc/inst/bin:$PATH
L=/root/xc/w-link
R=$L/runtime/winsup/cygwin
B=$L/bld/winsup/cygwin
D=/mnt/c/Users/crutkasLocal/.copilot/session-state/c63ab774-a023-4e57-9bc4-53f727507ada/files/runtest
F=$D/frozen-rung5
mkdir -p $F
cd $B || exit 1

cat > /tmp/rung5.c <<'EOF'
#include <stdio.h>
#include <signal.h>
#include <stdlib.h>

static volatile sig_atomic_t got = 0;

static void
handler (int sig)
{
  got = sig;
}

int
main (void)
{
  if (signal (SIGUSR1, handler) == SIG_ERR)
    {
      printf ("FAIL: signal() returned SIG_ERR\n");
      fflush (stdout);
      return 81;
    }
  printf ("handler installed\n");
  fflush (stdout);

  if (raise (SIGUSR1) != 0)
    {
      printf ("FAIL: raise() failed\n");
      fflush (stdout);
      return 82;
    }
  printf ("raise returned\n");
  fflush (stdout);

  if (got != SIGUSR1)
    {
      printf ("FAIL: handler did not run (got=%d)\n", (int) got);
      fflush (stdout);
      return 83;
    }
  printf ("handler RAN, signal=%d\n", (int) got);
  fflush (stdout);
  return 55;
}
EOF

aarch64-pc-cygwin-gcc -g -O0 -nostdlib -nostartfiles \
  -isystem $R/include -isystem /root/xc/bld/newlib/targ-include \
  -isystem $L/runtime/newlib/libc/include \
  -o rung5.exe $B/crt0.o /tmp/rung5.c $B/libmsys-2.0.a \
  -L/root/xc/build-gcc2/aarch64-pc-cygwin/libgcc -lgcc \
  -L/root/xc/implibs/lib -lkernel32 2>&1 | head -10
echo "LINK EXIT ${PIPESTATUS[0]}"

if [ -f rung5.exe ]; then
  cp rung5.exe $D/
  # FREEZE the exact pair under diagnosis.
  cp rung5.exe $F/rung5.exe
  cp new-msys-2.0.dll $F/msys-2.0.dll
  chmod a-w $F/rung5.exe $F/msys-2.0.dll
  echo
  echo "=== FROZEN PAIR (diagnose only these) ==="
  sha256sum $F/rung5.exe $F/msys-2.0.dll | sed 's|.*/| |'
fi
