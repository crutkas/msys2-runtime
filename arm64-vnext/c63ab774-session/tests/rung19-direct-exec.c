/* rung19 -- exec DIRECTLY from main, with no fork anywhere in the process.
 *
 * The discriminator for "is fork ancestry the variable?".  Run this against a
 * DLL with the exec fix reverted and compare with rung14 (fork then exec) on
 * the same DLL: if both fail identically, fork ancestry is not the variable.
 *
 * Measured result: identical failure in both arms -- child_copy err 6,
 * signal-pipe err 5.  Fork ancestry refuted as a factor.
 *
 * Expected with the fix: exit 77, i.e. the exec'd rung3.exe ran and returned
 * its own 77.  Exit 99 means execv returned (a real exec failure); anything
 * else means the exec'd image ran but returned something unexpected.
 */
#include <stdio.h>
#include <errno.h>
#include <unistd.h>

int
main (int argc, char **argv)
{
  const char *t = argc > 1 ? argv[1] : "rung3.exe";
  char *av[2];

  av[0] = (char *) t;
  av[1] = NULL;
  fprintf (stderr, "rung19: exec %s directly, NO fork first\n", t);
  execv (t, av);
  fprintf (stderr, "rung19: execv RETURNED errno=%d\n", errno);
  return 99;
}
