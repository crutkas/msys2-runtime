#!/bin/bash
set -u
export PATH=/root/xc/inst/bin:$PATH
L=/root/xc/w-link; R=$L/runtime/winsup/cygwin; B=$L/bld/winsup/cygwin
D=/mnt/c/Users/crutkasLocal/.copilot/session-state/c63ab774-a023-4e57-9bc4-53f727507ada/files/runtest
cd $B || exit 1
cat > /tmp/rung12.c <<'EOF'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/wait.h>
static int fails = 0;
#define CHECK(c,msg) do { if (c) printf("  ok   %s\n", msg); \
                          else { printf("  FAIL %s\n", msg); fails++; } } while (0)
int main (void)
{
  pid_t p; int st;
  printf ("T1 fork + waitpid + exit status\n");
  p = fork ();
  if (p == 0) _exit (7);
  CHECK (p > 0, "fork returned a pid");
  CHECK (waitpid (p, &st, 0) == p, "waitpid reaped the child");
  CHECK (WIFEXITED (st) && WEXITSTATUS (st) == 7, "child exit status is 7");

  printf ("T2 second fork after the first was reaped\n");
  p = fork ();
  if (p == 0) _exit (9);
  CHECK (p > 0, "second fork returned a pid");
  CHECK (waitpid (p, &st, 0) == p && WEXITSTATUS (st) == 9, "second child status 9");

  printf ("T3 pipe: child writes, parent reads\n");
  int fd[2];
  CHECK (pipe (fd) == 0, "pipe created");
  p = fork ();
  if (p == 0) { close (fd[0]); write (fd[1], "hello-from-child", 16); close (fd[1]); _exit (0); }
  close (fd[1]);
  char buf[32]; memset (buf, 0, sizeof buf);
  int n = read (fd[0], buf, sizeof buf - 1);
  close (fd[0]);
  waitpid (p, &st, 0);
  CHECK (n == 16, "parent read 16 bytes");
  CHECK (strcmp (buf, "hello-from-child") == 0, "pipe payload intact");

  printf ("T4 nested fork: child forks a grandchild\n");
  p = fork ();
  if (p == 0) {
      pid_t g = fork ();
      if (g == 0) _exit (21);
      int gs; waitpid (g, &gs, 0);
      _exit (WIFEXITED (gs) && WEXITSTATUS (gs) == 21 ? 22 : 23);
  }
  CHECK (waitpid (p, &st, 0) == p, "reaped the child that forked");
  CHECK (WIFEXITED (st) && WEXITSTATUS (st) == 22, "grandchild ran and was reaped by child");

  printf ("T5 heap work in the child (exercises the cygheap post-fork)\n");
  p = fork ();
  if (p == 0) {
      char *m = malloc (4096);
      if (!m) _exit (31);
      memset (m, 0xAB, 4096);
      int bad = 0; for (int i = 0; i < 4096; i++) if ((unsigned char) m[i] != 0xAB) bad = 1;
      free (m);
      _exit (bad ? 32 : 33);
  }
  waitpid (p, &st, 0);
  CHECK (WIFEXITED (st) && WEXITSTATUS (st) == 33, "child malloc/memset/free clean");

  printf ("RESULT %s (%d failures)\n", fails ? "FAIL" : "ALL PASS", fails);
  return fails ? 1 : 88;
}
EOF
aarch64-pc-cygwin-gcc -g -O0 -nostdlib -nostartfiles \
  -isystem $R/include -isystem /root/xc/bld/newlib/targ-include \
  -isystem $L/runtime/newlib/libc/include \
  -o rung12.exe $B/crt0.o /tmp/rung12.c $B/libmsys-2.0.a \
  -L/root/xc/build-gcc2/aarch64-pc-cygwin/libgcc -lgcc \
  -L/root/xc/implibs/lib -lkernel32 2>&1 | head -8
echo "LINK EXIT ${PIPESTATUS[0]}"
[ -f rung12.exe ] && cp rung12.exe $D/ && echo "staged rung12.exe"