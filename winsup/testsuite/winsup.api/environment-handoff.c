/* Inspect POSIX/private-envp and Windows environment transport independently. */
#include <windows.h>
#include <errno.h>
#include <process.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/cygwin.h>
#include <sys/wait.h>
#include <unistd.h>

static const char *names[] = {
  "WOA_INHERITED", "WOA_REPLACED", "WOA_NEW", "WOA_DELETED",
  "WOA_EMPTY", "WOA_MiXeD", "WOA_mixed", "WOA_MIXED", "WOA_UNICODE",
  "WOA_PATH", "WOA_OPAQUE", "WOA_LARGE_A", "WOA_LARGE_B",
  "WOA_LARGE_C", "WOA_LARGE_D", "CCACHE_DISABLE", "TMPDIR",
  "PATH", "MSYSTEM", "SYSTEMROOT", "WINDIR", NULL
};

static void
record (const char *kind, const char *name, const char *value)
{
  printf ("%s\t%s\t", kind, name);
  if (!value)
    putchar ('-');
  else
    for (const unsigned char *p = (const unsigned char *) value; *p; ++p)
      printf ("%02x", *p);
  putchar ('\n');
}

static void
record_wide (const char *kind, const char *name, const WCHAR *value)
{
  int count = WideCharToMultiByte (CP_UTF8, 0, value, -1, NULL, 0, NULL, NULL);
  if (!count)
    exit (90);
  char *text = malloc (count);
  if (!text || !WideCharToMultiByte (CP_UTF8, 0, value, -1, text, count,
				   NULL, NULL))
    exit (91);
  record (kind, name, text);
  free (text);
}

static void
inspect (int argc, char **argv)
{
  WCHAR module[32768];
  DWORD count = GetModuleFileNameW (GetModuleHandleW (L"msys-2.0.dll"),
				   module, 32768);
  if (!count || count >= 32768)
    exit (92);
  record_wide ("META", "runtime", module);
  printf ("PID\t%lu\t%ld\t%ld\n", (unsigned long) GetCurrentProcessId (),
	  (long) getpid (), (long) getppid ());
  for (const char **name = names; *name; ++name)
    {
      record ("POSIX", *name, getenv (*name));
      WCHAR key[80];
      if (!MultiByteToWideChar (CP_UTF8, 0, *name, -1, key, 80))
	exit (93);
      SetLastError (ERROR_SUCCESS);
      DWORD size = GetEnvironmentVariableW (key, NULL, 0);
      if (!size)
	record ("WIN", *name, GetLastError () == ERROR_ENVVAR_NOT_FOUND
			     ? NULL : "");
      else
	{
	  WCHAR *value = malloc (size * sizeof (*value));
	  if (!value || GetEnvironmentVariableW (key, value, size) >= size)
	    exit (94);
	  record_wide ("WIN", *name, value);
	  free (value);
	}
    }
  for (int i = 0; i < argc; ++i)
    {
      char index[24];
      snprintf (index, sizeof index, "%d", i);
      record ("ARG", index, argv[i]);
    }
  fflush (stdout);
}

static int
mutate (const char *phase)
{
  if (strcmp (phase, "inherited") == 0)
    return 0;
  if (setenv ("WOA_REPLACED", "replacement value", 1)
      || setenv ("WOA_NEW", "new value", 1)
      || unsetenv ("WOA_DELETED")
      || setenv ("WOA_EMPTY", "", 1)
      || unsetenv ("WOA_MIXED")
      || setenv ("WOA_MiXeD", "MixedCase", 1)
      || setenv ("WOA_UNICODE", "caf\xc3\xa9-\xe4\xb8\xad\xe6\x96\x87", 1)
      || setenv ("WOA_OPAQUE", "opaque=/do/not/rewrite;second=::", 1)
      || setenv ("CCACHE_DISABLE", "changed", 1))
    return -1;
  if (strcmp (phase, "large") == 0)
    {
      char large[10001];
      memset (large, 'q', sizeof large - 1);
      large[sizeof large - 1] = 0;
      for (int i = 0; i < 4; ++i)
	{
	  char name[] = "WOA_LARGE_A";
	  name[sizeof name - 2] += i;
	  if (setenv (name, large, 1))
	    return -1;
	}
    }
  return 0;
}

int
main (int argc, char **argv)
{
  SetErrorMode (0x8003);
  if (argc > 1 && strcmp (argv[1], "--inspect") == 0)
    {
      inspect (argc - 2, argv + 2);
      return 0;
    }
  if (argc > 1 && strcmp (argv[1], "--exit") == 0)
    return argc == 3 ? atoi (argv[2]) : 95;
  if (argc == 1)
    {
      if (setenv ("WOA_NEW", "same-runtime-private-env", 1))
	return 1;
      const char *child[] = {argv[0], "--self-check", NULL};
      int status = spawnv (_P_WAIT, argv[0], child);
      return status < 0 || !WIFEXITED (status) || WEXITSTATUS (status) != 0;
    }
  if (strcmp (argv[1], "--self-check") == 0)
    return !getenv ("WOA_NEW")
	   || strcmp (getenv ("WOA_NEW"), "same-runtime-private-env") != 0;
  if (argc < 5 || mutate (argv[2]))
    return 96;
  printf ("PARENT\t%lu\t%ld\n", (unsigned long) GetCurrentProcessId (),
	  (long) getpid ());
  fflush (stdout);
  if (strcmp (argv[1], "--exec") == 0)
    {
      execv (argv[3], argv + 3);
      fprintf (stderr, "execv failed: %d\n", errno);
      return 97;
    }
  int status;
  if (strcmp (argv[1], "--spawn") == 0)
    status = spawnv (_P_WAIT, argv[3], (const char * const *) (argv + 3));
  else if (strcmp (argv[1], "--spawn-nowait") == 0)
    {
      pid_t child = spawnv (_P_NOWAIT, argv[3],
			   (const char * const *) (argv + 3));
      if (child < 0 || waitpid (child, &status, 0) != child)
	return 98;
      printf ("WAITPID\t%ld\n", (long) child);
    }
  else
    return 99;
  printf ("STATUS\t%d\n", status);
  return status < 0 || !WIFEXITED (status) || WEXITSTATUS (status) != 0;
}
