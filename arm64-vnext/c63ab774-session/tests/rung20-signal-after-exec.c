/* rung20 -- signal delivery AFTER exec, and exit-status translation.
 *
 * exceptions.cc:1063 and :1714 gate signal handling after exec, and both were
 * on the wrong branch before the hookapi.cc ARM64 fix, because iscygwin() was
 * false for every AArch64 binary.  Nothing tested that path, so this rung was
 * built for it specifically.
 *
 * It proves two subsystems with one test:
 *   - the exec'd image installs a handler, raises, and exits 55 ONLY if the
 *     handler ran (that is rung5's contract), so a post-exec signal failure
 *     shows up as a wrong exit code;
 *   - the parent observes 55 through WEXITSTATUS rather than a raw Windows
 *     status, which exercises sigproc.cc:1204 exit-code translation.
 *
 * A failure in either subsystem fails this test.  Measured 5/5 after the fix.
 * Expected: exit 66.
 */
#include <stdio.h>
#include <errno.h>
#include <unistd.h>
#include <sys/wait.h>

int
main (int argc, char **argv)
{
  const char *t = argc > 1 ? argv[1] : "rung5.exe";
  pid_t p = fork ();

  if (p < 0)
    {
      printf ("FAIL fork errno=%d\n", errno);
      return 1;
    }
  if (p == 0)
    {
      char *av[2];
      av[0] = (char *) t;
      av[1] = NULL;
      execv (t, av);
      fprintf (stderr, "CHILD execv RETURNED errno=%d\n", errno);
      _exit (99);
    }

  int st;
  waitpid (p, &st, 0);
  if (!WIFEXITED (st))
    {
      printf ("post-exec signal test: child did NOT exit normally, raw 0x%x\n",
	      st);
      return 2;
    }

  int rc = WEXITSTATUS (st);
  printf ("post-exec signal test: exec'd %s exited %d %s\n", t, rc,
	  rc == 55 ? "<-- HANDLER RAN AFTER EXEC, status translated correctly"
		   : (rc == 99 ? "<-- execv returned" : "<-- WRONG"));
  return rc == 55 ? 66 : 1;
}
