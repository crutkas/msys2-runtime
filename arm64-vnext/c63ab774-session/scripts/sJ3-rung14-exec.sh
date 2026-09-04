#!/bin/bash
set -u
export PATH=/root/xc/inst/bin:$PATH
L=/root/xc/w-link; R=$L/runtime/winsup/cygwin; B=$L/bld/winsup/cygwin
D=/mnt/c/Users/crutkasLocal/.copilot/session-state/c63ab774-a023-4e57-9bc4-53f727507ada/files/runtest
cd $B || exit 1
# rung14: the exec gate.  child execv's rung3.exe (which just returns 77).
cat > /tmp/rung14.c <<'EOF'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>
#include <sys/wait.h>
int main (int argc, char **argv)
{
  pid_t p; int st;
  if (argc < 2) { printf ("usage: rung14 <path-to-rung3.exe>\n"); return 2; }
  printf ("T1 plain fork control\n");
  p = fork ();
  if (p == 0) _exit (5);
  if (p < 0) { printf ("  FAIL fork -1 errno=%d\n", errno); return 1; }
  waitpid (p, &st, 0);
  printf ("  fork ok, child status %d\n", WEXITSTATUS (st));

  printf ("T2 fork + execv of %s (expect exit 77)\n", argv[1]);
  p = fork ();
  if (p == 0)
    {
      char *av[2]; av[0] = argv[1]; av[1] = NULL;
      execv (argv[1], av);
      /* only reached if execv failed */
      fprintf (stderr, "  CHILD: execv returned, errno=%d\n", errno);
      _exit (99);
    }
  if (p < 0) { printf ("  FAIL fork -1 errno=%d\n", errno); return 1; }
  if (waitpid (p, &st, 0) != p) { printf ("  FAIL waitpid\n"); return 1; }
  if (!WIFEXITED (st)) { printf ("  FAIL child did not exit normally, status=0x%x\n", st); return 1; }
  int rc = WEXITSTATUS (st);
  printf ("  child exit = %d\n", rc);
  if (rc == 77) { printf ("RESULT EXEC WORKS\n"); return 66; }
  if (rc == 99) { printf ("RESULT EXECV RETURNED (exec failed, fork fine)\n"); return 3; }
  printf ("RESULT UNEXPECTED (%d)\n", rc);
  return 4;
}
EOF
aarch64-pc-cygwin-gcc -g -O0 -nostdlib -nostartfiles \
  -isystem $R/include -isystem /root/xc/bld/newlib/targ-include \
  -isystem $L/runtime/newlib/libc/include \
  -o rung14.exe $B/crt0.o /tmp/rung14.c $B/libmsys-2.0.a \
  -L/root/xc/build-gcc2/aarch64-pc-cygwin/libgcc -lgcc \
  -L/root/xc/implibs/lib -lkernel32 2>&1 | head -5
echo "LINK EXIT ${PIPESTATUS[0]}"
[ -f rung14.exe ] && cp rung14.exe $D/ && echo staged