/* Verify long arguments at process startup and across spawn/exec boundaries.

   Every child invocation carries the expected tail length explicitly.  The
   child parses that length strictly, requires an exact argument count, and
   requires strlen (tail) to equal the declared length before it inspects a
   single tail byte.  A truncated tail sent with the original declared length
   is therefore rejected instead of silently passing as a prefix, and each
   invocation model is exercised with exactly that negative control.  */

#include <windows.h>
#include <process.h>
#include <sys/cygwin.h>
#include <sys/wait.h>
#include <unistd.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

#define ARRAY_SIZE(a) (sizeof (a) / sizeof ((a)[0]))
#define MAX_ARG_LEN 4096
#define MAX_CMD_LEN 16384
#define TAIL_ALPHABET 23

/* Child exit codes.  CHILD_TAIL_LENGTH is what the negative controls
   require, so an accidental pass cannot be mistaken for a rejection.  */
#define CHILD_ARGC 101
#define CHILD_FILLER 102
#define CHILD_TAIL_LENGTH 103
#define CHILD_TAIL_BYTES 104
#define CHILD_LENGTH_PARSE 105
#define CHILD_WIDE_CONVERT 106
#define CHILD_RAW_MISSING 107
#define CHILD_RAW_NOT_FOUND 108
#define CHILD_RAW_AMBIGUOUS 109
#define CHILD_RAW_LEFT 110
#define CHILD_RAW_RIGHT 111

static char self_path[4096];
static char filler[MAX_ARG_LEN + 1];
static char tail[MAX_ARG_LEN + 1];
static char truncated_tail[MAX_ARG_LEN + 1];
static wchar_t wide_filler[MAX_ARG_LEN + 1];
static wchar_t wide_tail[MAX_ARG_LEN + 1];
static wchar_t wide_exe[4096];
static wchar_t command_line[MAX_CMD_LEN];

static char
tail_byte (size_t index)
{
  return (char) ('A' + (index % TAIL_ALPHABET));
}

static int
is_tail_wide (wchar_t value)
{
  return value >= L'A' && value <= (wchar_t) (L'A' + TAIL_ALPHABET - 1);
}

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
    tail[i] = tail_byte (i);
  tail[length] = '\0';
}

/* A strict prefix of the current tail, one byte short.  Sent together with
   the untruncated declared length so the child must reject it.  */
static void
make_truncated_tail (size_t length)
{
  memcpy (truncated_tail, tail, length);
  truncated_tail[length - 1] = '\0';
}

/* Strict decimal parse: no sign, no whitespace, no leading zero, no
   trailing characters, no overflow.  */
static int
parse_length (const char *text, size_t *out)
{
  size_t value = 0;

  if (!text || text[0] == '\0')
    return 0;
  if (text[0] == '0' && text[1] != '\0')
    return 0;
  for (const char *p = text; *p; ++p)
    {
      if (*p < '0' || *p > '9')
	return 0;
      if (value > (SIZE_MAX - (size_t) (*p - '0')) / 10)
	return 0;
      value = value * 10 + (size_t) (*p - '0');
    }
  *out = value;
  return 1;
}

/* Corroborate the tail against the raw wide command line.  The match must be
   unique and delimited on both sides by a byte outside the tail alphabet, so
   a prefix of the expected tail cannot satisfy the check.  */
static int
check_raw_command_line (const char *model, size_t expected)
{
  const wchar_t *raw = GetCommandLineW ();
  const wchar_t *match;

  if (!raw)
    {
      fprintf (stderr, "%s child has no raw command line\n", model);
      return CHILD_RAW_MISSING;
    }

  match = wcsstr (raw, wide_tail);
  if (!match)
    {
      fprintf (stderr, "%s child tail absent from raw command line\n", model);
      return CHILD_RAW_NOT_FOUND;
    }
  if (wcsstr (match + 1, wide_tail))
    {
      fprintf (stderr, "%s child tail is ambiguous in the raw command line\n",
	       model);
      return CHILD_RAW_AMBIGUOUS;
    }
  if (match != raw && is_tail_wide (match[-1]))
    {
      fprintf (stderr, "%s child raw tail is not left-delimited\n", model);
      return CHILD_RAW_LEFT;
    }
  if (is_tail_wide (match[expected]))
    {
      fprintf (stderr, "%s child raw tail is not right-delimited\n", model);
      return CHILD_RAW_RIGHT;
    }
  return 0;
}

static int
child_main (int argc, char **argv)
{
  size_t expected = 0;
  size_t actual;
  int converted;
  int status;

  if (argc != 6 || strcmp (argv[1], "--child") != 0)
    {
      fprintf (stderr, "child received argc=%d, expected 6\n", argc);
      return CHILD_ARGC;
    }

  if (!parse_length (argv[3], &expected)
      || expected == 0 || expected > MAX_ARG_LEN)
    {
      fprintf (stderr, "%s child rejected declared length \"%s\"\n",
	       argv[2], argv[3]);
      return CHILD_LENGTH_PARSE;
    }

  for (const char *p = argv[4]; *p; ++p)
    if (*p != 'f')
      {
	fprintf (stderr, "%s child filler corruption at %td\n",
		 argv[2], p - argv[4]);
	return CHILD_FILLER;
      }

  actual = strlen (argv[5]);
  if (actual != expected)
    {
      fprintf (stderr, "%s child tail length %zu, declared %zu\n",
	       argv[2], actual, expected);
      return CHILD_TAIL_LENGTH;
    }

  for (size_t i = 0; i < actual; ++i)
    if (argv[5][i] != tail_byte (i))
      {
	fprintf (stderr, "%s child tail corruption at %zu\n", argv[2], i);
	return CHILD_TAIL_BYTES;
      }

  converted = MultiByteToWideChar (CP_UTF8, MB_ERR_INVALID_CHARS,
				   argv[5], -1, wide_tail,
				   (int) ARRAY_SIZE (wide_tail));
  if (converted <= 0 || (size_t) (converted - 1) != expected)
    {
      fprintf (stderr, "%s child wide conversion produced %d units\n",
	       argv[2], converted);
      return CHILD_WIDE_CONVERT;
    }

  status = check_raw_command_line (argv[2], expected);
  if (status)
    return status;

  return 0;
}

static void
format_length (char *out, size_t size, size_t value)
{
  snprintf (out, size, "%lu", (unsigned long) value);
}

/* spawnve returns the raw waitpid status for _P_WAIT (see
   winsup/cygwin/spawn.cc), so the child's exit code has to be decoded
   rather than used directly; otherwise a child exit of 103 would surface
   as 26368.  The CreateProcessW model needs no such decoding: a child not
   started by Cygwin has its exit code byte-swapped back to the plain value
   in pinfo::exit, so GetExitCodeProcess already reports 103.  */
static int
run_spawn (const char *value, size_t expected, int *child_status)
{
  char declared[32];
  format_length (declared, sizeof (declared), expected);

  const char *args[] = {
    self_path, "--child", "spawnv", declared, filler, value, NULL
  };
  intptr_t status = spawnv (_P_WAIT, self_path, args);
  if (status < 0)
    return 120;

  int raw = (int) status;
  if (!WIFEXITED (raw))
    return 125;
  *child_status = WEXITSTATUS (raw);
  return 0;
}

static int
run_exec (const char *value, size_t expected, int *child_status)
{
  char declared[32];
  format_length (declared, sizeof (declared), expected);

  const char *args[] = {
    self_path, "--child", "execv", declared, filler, value, NULL
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
  *child_status = WEXITSTATUS (status);
  return 0;
}

/* Duplicate a standard handle as inheritable so the child's diagnostics are
   preserved.  stdout and stderr are required, so child output can never be
   silently discarded; a genuinely absent stdin is represented exactly rather
   than worked around.  Duplication failure is always reported.  */
static int
duplicate_inheritable (DWORD which, HANDLE *out, int required)
{
  HANDLE self = GetCurrentProcess ();
  HANDLE source = GetStdHandle (which);

  *out = NULL;
  if (source == NULL || source == INVALID_HANDLE_VALUE)
    return required ? 0 : 1;
  return DuplicateHandle (self, source, self, out, 0, TRUE,
			  DUPLICATE_SAME_ACCESS) ? 1 : 0;
}

static void
close_if_open (HANDLE handle)
{
  if (handle != NULL && handle != INVALID_HANDLE_VALUE)
    CloseHandle (handle);
}

static int
run_create_process (const char *value, size_t expected, int *child_status)
{
  HANDLE child_in = NULL;
  HANDLE child_out = NULL;
  HANDLE child_err = NULL;
  STARTUPINFOW startup;
  PROCESS_INFORMATION process;
  int result;

  if (!GetModuleFileNameW (NULL, wide_exe, (DWORD) ARRAY_SIZE (wide_exe)))
    return 130;
  if (!MultiByteToWideChar (CP_UTF8, MB_ERR_INVALID_CHARS, filler, -1,
			    wide_filler, (int) ARRAY_SIZE (wide_filler)))
    return 131;
  if (!MultiByteToWideChar (CP_UTF8, MB_ERR_INVALID_CHARS, value, -1,
			    wide_tail, (int) ARRAY_SIZE (wide_tail)))
    return 132;

  int length = swprintf (command_line, ARRAY_SIZE (command_line),
			 L"\"%ls\" --child win32 %lu \"%ls\" \"%ls\"",
			 wide_exe, (unsigned long) expected, wide_filler,
			 wide_tail);
  if (length < 0 || (size_t) length >= ARRAY_SIZE (command_line))
    return 133;

  if (!duplicate_inheritable (STD_INPUT_HANDLE, &child_in, 0)
      || !duplicate_inheritable (STD_OUTPUT_HANDLE, &child_out, 1)
      || !duplicate_inheritable (STD_ERROR_HANDLE, &child_err, 1))
    {
      close_if_open (child_in);
      close_if_open (child_out);
      close_if_open (child_err);
      return 135;
    }

  memset (&startup, 0, sizeof (startup));
  memset (&process, 0, sizeof (process));
  startup.cb = sizeof (startup);
  startup.dwFlags = STARTF_USESTDHANDLES;
  startup.hStdInput = child_in;
  startup.hStdOutput = child_out;
  startup.hStdError = child_err;

  if (!CreateProcessW (NULL, command_line, NULL, NULL, TRUE, 0, NULL, NULL,
		       &startup, &process))
    {
      close_if_open (child_in);
      close_if_open (child_out);
      close_if_open (child_err);
      return 134;
    }

  close_if_open (child_in);
  close_if_open (child_out);
  close_if_open (child_err);

  DWORD wait = WaitForSingleObject (process.hProcess, 60000);
  if (wait == WAIT_TIMEOUT)
    {
      if (!TerminateProcess (process.hProcess, 0xDEAD))
	result = 139;
      else
	{
	  WaitForSingleObject (process.hProcess, INFINITE);
	  result = 136;
	}
    }
  else if (wait != WAIT_OBJECT_0)
    result = 137;
  else
    {
      DWORD code = 0;
      if (!GetExitCodeProcess (process.hProcess, &code))
	result = 138;
      else
	{
	  *child_status = (int) code;
	  result = 0;
	}
    }

  CloseHandle (process.hThread);
  CloseHandle (process.hProcess);
  return result;
}

struct invocation
{
  const char *name;
  int (*run) (const char *, size_t, int *);
};

static const struct invocation invocations[] = {
  { "spawnv", run_spawn },
  { "execv", run_exec },
  { "CreateProcessW", run_create_process },
};

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

	for (size_t k = 0; k < ARRAY_SIZE (invocations); ++k)
	  {
	    int child_status = -1;
	    int harness = invocations[k].run (tail, tail_lengths[j],
					      &child_status);
	    if (harness != 0)
	      {
		fprintf (stderr,
			 "%s harness failure: filler=%zu tail=%zu status=%d\n",
			 invocations[k].name, filler_lengths[i],
			 tail_lengths[j], harness);
		return 2;
	      }
	    if (child_status != 0)
	      {
		fprintf (stderr,
			 "%s failed: filler=%zu tail=%zu child=%d\n",
			 invocations[k].name, filler_lengths[i],
			 tail_lengths[j], child_status);
		return 3;
	      }
	  }
      }

  /* Negative controls.  Each model resends a tail that is one byte short
     while still declaring the original length; the child must reject it with
     exactly CHILD_TAIL_LENGTH.  Any other outcome, including success, means
     the positive assertions above are not actually discriminating.  */
  make_filler (16);
  for (size_t j = 0; j < ARRAY_SIZE (tail_lengths); ++j)
    {
      make_tail (tail_lengths[j]);
      make_truncated_tail (tail_lengths[j]);

      for (size_t k = 0; k < ARRAY_SIZE (invocations); ++k)
	{
	  int child_status = -1;
	  int harness = invocations[k].run (truncated_tail, tail_lengths[j],
					    &child_status);
	  if (harness != 0)
	    {
	      fprintf (stderr,
		       "%s negative-control harness failure: tail=%zu "
		       "status=%d\n", invocations[k].name, tail_lengths[j],
		       harness);
	      return 4;
	    }
	  if (child_status != CHILD_TAIL_LENGTH)
	    {
	      fprintf (stderr,
		       "%s negative control expected child=%d, observed %d "
		       "for tail=%zu\n", invocations[k].name,
		       CHILD_TAIL_LENGTH, child_status, tail_lengths[j]);
	      return 5;
	    }
	}
    }

  return 0;
}
