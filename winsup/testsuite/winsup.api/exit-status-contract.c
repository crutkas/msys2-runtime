/* Copyright (C) 2026 Cygwin Authors

This file is part of Cygwin.

This software is a copyrighted work licensed under the terms of the
Cygwin license.  Please consult the file "CYGWIN_LICENSE" for
details. */

#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <sys/cygwin.h>
#include <sys/wait.h>
#include <unistd.h>
#include <wchar.h>
#include <windows.h>

static int
check_native_parent_exit (void)
{
  wchar_t path[MAX_PATH];
  wchar_t command[MAX_PATH + 32];
  STARTUPINFOW startup = { 0 };
  PROCESS_INFORMATION process = { 0 };
  DWORD raw_exit;

  if (!GetModuleFileNameW (NULL, path, MAX_PATH)
      || swprintf (command, MAX_PATH + 32, L"\"%ls\" --direct-child",
		   path) < 0)
    {
      fprintf (stderr, "cannot construct direct child command: %u\n",
	       GetLastError ());
      return 1;
    }

  startup.cb = sizeof startup;
  if (!CreateProcessW (NULL, command, NULL, NULL, FALSE, 0, NULL, NULL,
		       &startup, &process))
    {
      fprintf (stderr, "CreateProcessW failed: %u\n", GetLastError ());
      return 1;
    }

  CloseHandle (process.hThread);
  if (WaitForSingleObject (process.hProcess, 30000) != WAIT_OBJECT_0
      || !GetExitCodeProcess (process.hProcess, &raw_exit))
    {
      fprintf (stderr, "direct child wait failed: %u\n", GetLastError ());
      CloseHandle (process.hProcess);
      return 1;
    }
  CloseHandle (process.hProcess);

  if (raw_exit != 126)
    {
      fprintf (stderr, "native-parent raw exit %u, expected 126\n",
	       raw_exit);
      return 1;
    }
  return 0;
}

static int
check_registered_child_wait_status (void)
{
  int sync_pipe[2];
  int status;
  pid_t pid;
  DWORD winpid;
  DWORD raw_exit;
  HANDLE process;
  char byte = 0;

  if (pipe (sync_pipe) != 0)
    {
      perror ("pipe");
      return 1;
    }

  pid = fork ();
  if (pid < 0)
    {
      perror ("fork");
      close (sync_pipe[0]);
      close (sync_pipe[1]);
      return 1;
    }
  if (pid == 0)
    {
      close (sync_pipe[1]);
      if (read (sync_pipe[0], &byte, 1) != 1)
	_exit (125);
      _exit (7);
    }

  close (sync_pipe[0]);
  winpid = (DWORD) cygwin_internal (CW_CYGWIN_PID_TO_WINPID, pid);
  process = OpenProcess (SYNCHRONIZE | PROCESS_QUERY_LIMITED_INFORMATION,
			 FALSE, winpid);
  if (!process)
    {
      fprintf (stderr, "OpenProcess(%u) failed: %u\n",
	       winpid, GetLastError ());
      close (sync_pipe[1]);
      waitpid (pid, NULL, 0);
      return 1;
    }

  if (write (sync_pipe[1], &byte, 1) != 1)
    {
      perror ("write");
      CloseHandle (process);
      close (sync_pipe[1]);
      waitpid (pid, NULL, 0);
      return 1;
    }
  close (sync_pipe[1]);

  if (waitpid (pid, &status, 0) != pid
      || WaitForSingleObject (process, 30000) != WAIT_OBJECT_0
      || !GetExitCodeProcess (process, &raw_exit))
    {
      fprintf (stderr, "registered child wait failed: %s (%u)\n",
	       strerror (errno), GetLastError ());
      CloseHandle (process);
      return 1;
    }
  CloseHandle (process);

  if (raw_exit != (7U << 8) || status != (7 << 8)
      || !WIFEXITED (status) || WEXITSTATUS (status) != 7)
    {
      fprintf (stderr,
	       "registered child raw=%u wait=%d exited=%d status=%d\n",
	       raw_exit, status, WIFEXITED (status),
	       WIFEXITED (status) ? WEXITSTATUS (status) : -1);
      return 1;
    }
  return 0;
}

int
main (int argc, char **argv)
{
  if (argc == 2 && strcmp (argv[1], "--direct-child") == 0)
    _exit (126);
  if (argc != 1)
    return 2;

  return check_native_parent_exit () || check_registered_child_wait_status ();
}
