/* Copyright (C) 2026 Cygwin Authors

This file is part of Cygwin.

This software is a copyrighted work licensed under the terms of the
Cygwin license.  Please consult the file "CYGWIN_LICENSE" for
details. */

#include <errno.h>
#include <limits.h>
#include <process.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

extern int execvpe (const char *, char *const [], char *const []);

static int
check_execvp_errno (const char *path, const char *file, int expected)
{
  char *const argv[] = {(char *) file, NULL};

  if (setenv ("PATH", path, 1) != 0)
    {
      perror ("setenv");
      return 1;
    }

  errno = 0;
  if (execvp (file, argv) != -1)
    {
      fprintf (stderr, "execvp unexpectedly succeeded for PATH=%s\n", path);
      return 1;
    }
  if (errno != expected)
    {
      fprintf (stderr, "execvp PATH=%s returned errno %d, expected %d\n",
	       path, errno, expected);
      return 1;
    }
  return 0;
}

static int
check_execlp_errno (const char *path, const char *file, int expected)
{
  if (setenv ("PATH", path, 1) != 0)
    {
      perror ("setenv");
      return 1;
    }

  errno = 0;
  if (execlp (file, file, NULL) != -1)
    {
      fprintf (stderr, "execlp unexpectedly succeeded for PATH=%s\n", path);
      return 1;
    }
  if (errno != expected)
    {
      fprintf (stderr, "execlp PATH=%s returned errno %d, expected %d\n",
	       path, errno, expected);
      return 1;
    }
  return 0;
}

static int
check_execvpe_errno (const char *path, const char *file, int expected)
{
  char *const argv[] = {(char *) file, NULL};

  if (setenv ("PATH", path, 1) != 0)
    {
      perror ("setenv");
      return 1;
    }

  errno = 0;
  if (execvpe (file, argv, environ) != -1)
    {
      fprintf (stderr, "execvpe unexpectedly succeeded for PATH=%s\n", path);
      return 1;
    }
  if (errno != expected)
    {
      fprintf (stderr, "execvpe PATH=%s returned errno %d, expected %d\n",
	       path, errno, expected);
      return 1;
    }
  return 0;
}

static int
check_spawnvp_errno (const char *path, const char *file, int expected)
{
  const char *const argv[] = {file, NULL};

  if (setenv ("PATH", path, 1) != 0)
    {
      perror ("setenv");
      return 1;
    }

  errno = 0;
  if (spawnvp (_P_WAIT, file, argv) != -1)
    {
      fprintf (stderr, "spawnvp unexpectedly succeeded for PATH=%s\n", path);
      return 1;
    }
  if (errno != expected)
    {
      fprintf (stderr, "spawnvp PATH=%s returned errno %d, expected %d\n",
	       path, errno, expected);
      return 1;
    }
  return 0;
}

static int
check_spawnvpe_errno (const char *path, const char *file, int expected)
{
  const char *const argv[] = {file, NULL};

  if (setenv ("PATH", path, 1) != 0)
    {
      perror ("setenv");
      return 1;
    }

  errno = 0;
  if (spawnvpe (_P_WAIT, file, argv, (const char *const *) environ) != -1)
    {
      fprintf (stderr, "spawnvpe unexpectedly succeeded for PATH=%s\n", path);
      return 1;
    }
  if (errno != expected)
    {
      fprintf (stderr, "spawnvpe PATH=%s returned errno %d, expected %d\n",
	       path, errno, expected);
      return 1;
    }
  return 0;
}

static int
check_posix_spawnp_error (const char *path, const char *file, int expected)
{
  char *const argv[] = {(char *) file, NULL};
  pid_t pid;
  int err;

  if (setenv ("PATH", path, 1) != 0)
    {
      perror ("setenv");
      return 1;
    }

  err = posix_spawnp (&pid, file, NULL, NULL, argv, environ);
  if (err != expected)
    {
      fprintf (stderr, "posix_spawnp PATH=%s returned %d, expected %d\n",
	       path, err, expected);
      return 1;
    }
  return 0;
}

int
main (void)
{
  char tmpdir[] = "execvp-path.XXXXXX";
  char candidate[PATH_MAX];
  char missing[PATH_MAX];
  char path[PATH_MAX * 2 + 2];
  int ret = 0;

  if (!mkdtemp (tmpdir))
    {
      perror ("mkdtemp");
      return 1;
    }
  if (snprintf (candidate, sizeof candidate, "%s/candidate", tmpdir)
      >= (int) sizeof candidate
      || mkdir (candidate, 0700) != 0)
    {
      perror ("mkdir");
      rmdir (tmpdir);
      return 1;
    }
  if (snprintf (missing, sizeof missing, "%s/missing", tmpdir)
      >= (int) sizeof missing)
    {
      fprintf (stderr, "temporary path is too long\n");
      ret = 1;
      goto out;
    }

  ret |= check_execvp_errno (tmpdir, "candidate", EACCES);
  snprintf (path, sizeof path, "%s:%s", missing, tmpdir);
  ret |= check_execvp_errno (path, "candidate", EACCES);
  snprintf (path, sizeof path, "%s:%s", tmpdir, missing);
  ret |= check_execvp_errno (path, "candidate", EACCES);
  ret |= check_execvp_errno (missing, "candidate", ENOENT);

  ret |= check_execlp_errno (tmpdir, "candidate", EACCES);
  ret |= check_execlp_errno (missing, "candidate", ENOENT);
  ret |= check_execvpe_errno (tmpdir, "candidate", EACCES);
  ret |= check_execvpe_errno (missing, "candidate", ENOENT);
  ret |= check_spawnvp_errno (tmpdir, "candidate", EACCES);
  ret |= check_spawnvp_errno (missing, "candidate", ENOENT);
  ret |= check_spawnvpe_errno (tmpdir, "candidate", EACCES);
  ret |= check_spawnvpe_errno (missing, "candidate", ENOENT);
  ret |= check_posix_spawnp_error (tmpdir, "candidate", EACCES);
  ret |= check_posix_spawnp_error (missing, "candidate", ENOENT);

out:
  rmdir (candidate);
  rmdir (tmpdir);
  return ret;
}
