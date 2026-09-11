/* Check the current import and both versioned uname export layouts. */
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>
#include <sys/utsname.h>

struct old_utsname
{
  char sysname[21];
  char nodename[20];
  char release[20];
  char version[20];
  char machine[20];
};

static int
check_machine (const char *entry, const char *machine, const char *expected)
{
  if (strcmp (machine, expected) == 0)
    return 0;
  fprintf (stderr, "%s machine is '%s', expected '%s'\n",
	   entry, machine, expected);
  return 1;
}

int
main (void)
{
#if defined (__aarch64__)
  const char *expected = "aarch64";
#elif defined (__x86_64__)
  const char *expected = "x86_64";
#else
  return 77;
#endif
  struct utsname current;
  struct old_utsname legacy;
  int failures = 0;
  int (*current_export) (struct utsname *);
  int (*legacy_export) (struct old_utsname *);

  current_export = (int (*) (struct utsname *)) dlsym (RTLD_DEFAULT, "uname_x");
  legacy_export = (int (*) (struct old_utsname *)) dlsym (RTLD_DEFAULT, "uname");
  if (!current_export || !legacy_export)
    {
      fprintf (stderr, "Missing current or legacy uname export: %s\n", dlerror ());
      return 1;
    }
  if (uname (&current) != 0)
    {
      perror ("uname");
      return 1;
    }
  failures += check_machine ("uname import", current.machine, expected);
  if (current_export (&current) != 0)
    {
      perror ("uname_x export");
      return 1;
    }
  failures += check_machine ("uname_x export", current.machine, expected);
  if (legacy_export (&legacy) != 0)
    {
      perror ("uname legacy export");
      return 1;
    }
  failures += check_machine ("uname legacy export", legacy.machine, expected);
  return failures != 0;
}
