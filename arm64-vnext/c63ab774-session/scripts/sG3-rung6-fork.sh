#!/bin/bash
# Rung 5b: fork(). The hardest thing in the programme.
set -u
export PATH=/root/xc/inst/bin:$PATH
L=/root/xc/w-link
R=$L/runtime/winsup/cygwin
B=$L/bld/winsup/cygwin
D=/mnt/c/Users/crutkasLocal/.copilot/session-state/c63ab774-a023-4e57-9bc4-53f727507ada/files/runtest
F=$D/frozen-rung5
cd $B || exit 1

cat > /tmp/rung6.c <<'EOF'
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/wait.h>

int
main (void)
{
  pid_t pid;
  int status;

  printf ("parent pid=%d, about to fork\n", (int) getpid ());
  fflush (stdout);

  pid = fork ();

  if (pid < 0)
    {
      printf ("FAIL: fork() returned %d\n", (int) pid);
      fflush (stdout);
      return 71;
    }

  if (pid == 0)
    {
      /* child */
      printf ("CHILD running, pid=%d\n", (int) getpid ());
      fflush (stdout);
      _exit (33);
    }

  printf ("PARENT continues, child pid=%d\n", (int) pid);
  fflush (stdout);

  if (waitpid (pid, &status, 0) != pid)
    {
      printf ("FAIL: waitpid did not return child pid\n");
      fflush (stdout);
      return 72;
    }

  if (!WIFEXITED (status))
    {
      printf ("FAIL: child did not exit normally, status=%d\n", status);
      fflush (stdout);
      return 73;
    }

  printf ("child exited with %d\n", WEXITSTATUS (status));
  fflush (stdout);

  if (WEXITSTATUS (status) != 33)
    return 74;

  return 66;
}
EOF

aarch64-pc-cygwin-gcc -g -O0 -nostdlib -nostartfiles \
  -isystem $R/include -isystem /root/xc/bld/newlib/targ-include \
  -isystem $L/runtime/newlib/libc/include \
  -o rung6.exe $B/crt0.o /tmp/rung6.c $B/libmsys-2.0.a \
  -L/root/xc/build-gcc2/aarch64-pc-cygwin/libgcc -lgcc \
  -L/root/xc/implibs/lib -lkernel32 2>&1 | head -10
echo "LINK EXIT ${PIPESTATUS[0]}"

if [ -f rung6.exe ]; then
  cp rung6.exe $D/ && cp rung6.exe $F/rung6.exe && chmod a-w $F/rung6.exe
  echo "rung6.exe sha256 $(sha256sum rung6.exe | cut -d' ' -f1)"
fi
