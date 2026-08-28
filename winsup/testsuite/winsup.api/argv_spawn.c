/* Verify long arguments at process startup and across spawn/exec boundaries. */

#include <windows.h>
#include <process.h>
#include <sys/cygwin.h>
#include <sys/wait.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

#define ARRAY_SIZE(a) (sizeof (a) / sizeof ((a)[0]))
#define MAX_ARG_LEN 4096
#define MAX_CMD_LEN 16384

static char self_path[4096];
static char filler[MAX_ARG_LEN + 1];
static char tail[MAX_ARG_LEN + 1];
static wchar_t wide_filler[MAX_ARG_LEN + 1];
static wchar_t wide_tail[MAX_ARG_LEN + 1];
static wchar_t wide_exe[4096];
static wchar_t command_line[MAX_CMD_LEN];

static void
make_filler (size_t length)
{
  memset (filler, 'f', length);
  filler[length] = '\0';
}

static void
make_tail (size_t length)
{
  for (size_t i = 0; i < length; ++i)
    tail[i] = 'A' + (i % 23);
  tail[length] = '\0';
}

static int
valid_tail (const char *value)
{
  size_t length = strlen (value);
  if (length == 0 || length > MAX_ARG_LEN)
    return 0;
  for (size_t i = 0; i < length; ++i)
    if (value[i] != 'A' + (i % 23))
      return 0;
  return 1;
}

static int
child_main (int argc, char **argv)
{
  if (argc != 5 || strcmp (argv[1], "--child") != 0)
    {
      fprintf (stderr, "child received argc=%d\n", argc);
      return 101;
    }

  for (const char *p = argv[3]; *p; ++p)
    if (*p != 'f')
      {
	fprintf (stderr, "%s child filler corruption at %td\n",
		 argv[2], p - argv[3]);
	return 102;
      }

  if (!valid_tail (argv[4]))
    {
      fprintf (stderr, "%s child tail corruption, length=%zu\n",
	       argv[2], strlen (argv[4]));
      return 103;
    }

  int converted = MultiByteToWideChar (CP_UTF8, MB_ERR_INVALID_CHARS,
				       argv[4], -1, wide_tail,
				       ARRAY_SIZE (wide_tail));
  if (!converted || !wcsstr (GetCommandLineW (), wide_tail))
    {
      fprintf (stderr, "%s child raw command line mismatch\n", argv[2]);
      return 104;
    }

  return 0;
}

static int
run_spawn (void)
{
  const char *args[] = {
    self_path, "--child", "spawnv", filler, tail, NULL
  };
  intptr_t status = spawnv (_P_WAIT, self_path, args);
  return status < 0 ? 120 : (int) status;
}

static int
run_exec (void)
{
  const char *args[] = {
    self_path, "--child", "execv", filler, tail, NULL
  };
  pid_t pid = fork ();
  if (pid == 0)
    {
      execv (self_path, (char * const *) args);
      _exit (121);
    }
  if (pid < 0)
    return 122;

  int status;
  if (waitpid (pid, &status, 0) != pid)
    return 123;
  if (!WIFEXITED (status))
    return 124;
  return WEXITSTATUS (status);
}

static int
run_create_process (void)
{
  if (!GetModuleFileNameW (NULL, wide_exe, ARRAY_SIZE (wide_exe)))
    return 130;
  if (!MultiByteToWideChar (CP_UTF8, MB_ERR_INVALID_CHARS, filler, -1,
			    wide_filler, ARRAY_SIZE (wide_filler)))
    return 131;
  if (!MultiByteToWideChar (CP_UTF8, MB_ERR_INVALID_CHARS, tail, -1,
			    wide_tail, ARRAY_SIZE (wide_tail)))
    return 132;

  int length = swprintf (command_line, ARRAY_SIZE (command_line),
			 L"\"%ls\" --child win32 \"%ls\" \"%ls\"",
			 wide_exe, wide_filler, wide_tail);
  if (length < 0 || (size_t) length >= ARRAY_SIZE (command_line))
    return 133;

  STARTUPINFOW startup;
  PROCESS_INFORMATION process;
  memset (&startup, 0, sizeof (startup));
  memset (&process, 0, sizeof (process));
  startup.cb = sizeof (startup);
  if (!CreateProcessW (NULL, command_line, NULL, NULL, FALSE, 0, NULL, NULL,
		       &startup, &process))
    return 134;

  DWORD wait = WaitForSingleObject (process.hProcess, 30000);
  DWORD status = 135;
  if (wait == WAIT_OBJECT_0)
    GetExitCodeProcess (process.hProcess, &status);
  CloseHandle (process.hThread);
  CloseHandle (process.hProcess);
  return (int) status;
}

int
main (int argc, char **argv)
{
  if (argc > 1 && strcmp (argv[1], "--child") == 0)
    return child_main (argc, argv);

  ssize_t length = readlink ("/proc/self/exe", self_path,
			     sizeof (self_path) - 1);
  if (length <= 0 || (size_t) length >= sizeof (self_path))
    {
      perror ("readlink /proc/self/exe");
      return 1;
    }
  self_path[length] = '\0';

  static const size_t filler_lengths[] = { 0, 1, 15, 16, 17, 31 };
  static const size_t tail_lengths[] = { 511, 640, 1023, 2047, 4095 };

  for (size_t i = 0; i < ARRAY_SIZE (filler_lengths); ++i)
    for (size_t j = 0; j < ARRAY_SIZE (tail_lengths); ++j)
      {
	make_filler (filler_lengths[i]);
	make_tail (tail_lengths[j]);

	int status = run_spawn ();
	if (status)
	  {
	    fprintf (stderr, "spawnv failed: filler=%zu tail=%zu status=%d\n",
		     filler_lengths[i], tail_lengths[j], status);
	    return 2;
	  }

	status = run_exec ();
	if (status)
	  {
	    fprintf (stderr, "execv failed: filler=%zu tail=%zu status=%d\n",
		     filler_lengths[i], tail_lengths[j], status);
	    return 3;
	  }

	status = run_create_process ();
	if (status)
	  {
	    fprintf (stderr,
		     "CreateProcessW failed: filler=%zu tail=%zu status=%d\n",
		     filler_lengths[i], tail_lengths[j], status);
	    return 4;
	  }
      }

  return 0;
}
