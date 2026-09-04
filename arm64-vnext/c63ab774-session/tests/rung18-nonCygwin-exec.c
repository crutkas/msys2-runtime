/* rung18 -- exec of a NON-Cygwin (native Windows) program.
 *
 * Deliberately passes NO arguments: MSYS2 converts POSIX-looking arguments
 * such as "/c" into Windows paths, which confounds the result.  With no
 * arguments there is nothing to convert, so a failure here is an exec
 * failure and not an argument-marshalling artefact.
 *
 * hostname.exe prints and exits 0, so exit 0 proves the image really ran to
 * completion rather than merely being created.
 *
 * Used to refute the claim that spawn.cc's if (!iscygwin ()) inherit-clear
 * breaks exec of non-Cygwin programs.  It does not: a non-Cygwin child never
 * runs cygheap_fixup_in_child and has no use for the parent handle.
 *
 * Build: see scripts/ for the pattern -- crt0.o + libmsys-2.0.a, -nostdlib
 * -nostartfiles, -D__MSYS__ not required for the test itself.
 * Expected: exit 66.
 */
#include <stdio.h>
#include <errno.h>
#include <unistd.h>
#include <sys/wait.h>

int
main (void)
{
  const char *cmd = "C:\\Windows\\System32\\hostname.exe";
  pid_t p = fork ();
  if (p < 0)
    {
      printf ("FAIL fork errno=%d\n", errno);
      return 1;
    }
  if (p == 0)
    {
      char *av[2];
      av[0] = (char *) cmd;
      av[1] = NULL;
      execv (cmd, av);
      fprintf (stderr, "CHILD execv RETURNED errno=%d\n", errno);
      _exit (99);
    }

  int st;
  waitpid (p, &st, 0);
  if (WIFEXITED (st))
    {
      int rc = WEXITSTATUS (st);
      printf ("non-Cygwin exec (no args): child exited %d %s\n", rc,
	      rc == 0 ? "<-- WORKS, image ran to completion"
		      : (rc == 99 ? "<-- execv RETURNED, real failure"
				  : "<-- ran but nonzero"));
      return rc == 0 ? 66 : 1;
    }
  printf ("child did NOT exit normally, raw 0x%x\n", st);
  return 2;
}
