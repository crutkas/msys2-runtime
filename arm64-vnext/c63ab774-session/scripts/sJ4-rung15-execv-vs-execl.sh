#!/bin/bash
set -u
export PATH=/root/xc/inst/bin:$PATH
L=/root/xc/w-link; R=$L/runtime/winsup/cygwin; B=$L/bld/winsup/cygwin
D=/mnt/c/Users/crutkasLocal/.copilot/session-state/c63ab774-a023-4e57-9bc4-53f727507ada/files/runtest
cd $B || exit 1
cat > /tmp/rung15.c <<'EOF'
/* One binary, one run, two arms: execv vs execl against the SAME target.
   Isolates the call form as the only variable. */
#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <unistd.h>
#include <sys/wait.h>

static int
run_arm (const char *label, const char *target, int use_execl)
{
  pid_t p = fork ();
  if (p < 0) { printf ("%s: FAIL fork -1 errno=%d\n", label, errno); return -1; }
  if (p == 0)
    {
      if (use_execl)
	execl (target, target, (char *) NULL);
      else
	{
	  char *av[2]; av[0] = (char *) target; av[1] = NULL;
	  execv (target, av);
	}
      fprintf (stderr, "%s: CHILD exec RETURNED errno=%d\n", label, errno);
      _exit (99);
    }
  int st;
  if (waitpid (p, &st, 0) != p) { printf ("%s: FAIL waitpid\n", label); return -1; }
  if (WIFEXITED (st))
    {
      int rc = WEXITSTATUS (st);
      printf ("%s: exited %d  %s\n", label, rc,
	      rc == 77 ? "<-- EXEC WORKED" : (rc == 99 ? "<-- exec RETURNED (failed, no crash)" : ""));
      return rc;
    }
  printf ("%s: did NOT exit normally, raw status 0x%x\n", label, st);
  return -2;
}

int main (int argc, char **argv)
{
  const char *target = argc > 1 ? argv[1] : "rung3.exe";
  printf ("target=%s (expect 77 on success)\n", target);
  int v = run_arm ("execv", target, 0);
  int l = run_arm ("execl", target, 1);
  printf ("SUMMARY execv=%d execl=%d  %s\n", v, l,
	  v == l ? "IDENTICAL -- call form is NOT the variable"
		 : "DIFFERENT -- call form MATTERS");
  return (v == 77 && l == 77) ? 66 : 1;
}
EOF
aarch64-pc-cygwin-gcc -g -O0 -nostdlib -nostartfiles \
  -isystem $R/include -isystem /root/xc/bld/newlib/targ-include \
  -isystem $L/runtime/newlib/libc/include \
  -o rung15.exe $B/crt0.o /tmp/rung15.c $B/libmsys-2.0.a \
  -L/root/xc/build-gcc2/aarch64-pc-cygwin/libgcc -lgcc \
  -L/root/xc/implibs/lib -lkernel32 2>&1 | head -5
echo "LINK EXIT ${PIPESTATUS[0]}"
[ -f rung15.exe ] && cp rung15.exe $D/ && echo staged